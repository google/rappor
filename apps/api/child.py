# Copyright 2012 Google Inc.  All rights reserved.
# Use of this source code is governed by a BSD-style license that can be found
# in the COPYING file.

"""
child.py: Manage child processes (e.g. a pool of R interpreters).
"""

import errno
import json
import logging
import os
import Queue
import signal
import subprocess
import time


class ReplicaTimeoutError(Exception):
  pass


def MakeDirs(d):
  """Make a directory, doing nothing if it already exists."""
  try:
    os.makedirs(d)
  except OSError, e:
    # OK if it exists
    if e.errno != errno.EEXIST:
      raise


class Child(object):
  """A child process which communicates over a pair of FIFOs."""

  def __init__(self, argv, env=None, cwd=None, log_fd=None):
    """
    Args:
      argv: argument array
      env: environment dictionary for the process
      cwd: working directory
      log_fd: if specified, then stdout or stderr is redirect to this
        descriptor.
    """
    # By default, we kill with SIGKILL.  Applications might want to request
    # SIGTERM if they do something special.  TODO: Is SIGTERM better?  Then an
    # application can flush logs, etc.  That's probably why it's better to log
    # to stderr.
    self.argv = argv  # for DataDict
    self.env = env
    self.cwd = cwd
    self.log_fd = log_fd

    self.req_fifo_name = os.path.join(self.cwd, 'request-fifo')
    self.req_fifo_fd = -1

    self.resp_fifo_name = os.path.join(self.cwd, 'response-fifo')
    self.resp_fifo_fd = -1
    self.response_f = None

    self.name = argv[0]  # for __str__

    # These attributes are unknown here and set by Start()
    self.pid = None
    self.p = None  # set by Start

  def __str__(self):
    return '<Child %s %s>' % (self.pid, self.name)

  def __repr__(self):
    return self.__str__()

  def Start(self):
    """Start the process."""

    # kwargs for subprocess.Popen.  Prepare them here in the constructor; not
    # used until Start().
    kwargs = {}

    if self.cwd:
      kwargs['cwd'] = self.cwd

    # Set up environment
    if self.env:
      new_env = dict(os.environ)  # Make a copy
      new_env.update(self.env)  # update with server/user environment
      kwargs['env'] = new_env

    self._MaybeRemoveResponseFifo()
    os.mkfifo(self.resp_fifo_name)
    # Need to use rw mode even though we only read.  This is to make the
    # open non-blocking, but the reads blocking.
    self.resp_fifo_fd = os.open(self.resp_fifo_name, os.O_RDWR)
    self.response_f = os.fdopen(self.resp_fifo_fd)

    if self.log_fd:
      # If the response output is stdout, direct stderr to the debug log.  If
      # it's not (e.g. a named pipe), redirect both stdout and stderr.
      kwargs['stdout'] = self.log_fd
      kwargs['stderr'] = subprocess.STDOUT

    # Create request fifo if necessary
    self._MaybeRemoveRequestFifo()
    os.mkfifo(self.req_fifo_name)
    #self.req_fifo_fd = os.open(self.req_fifo_name, os.O_RDWR|os.O_NONBLOCK)
    self.req_fifo_fd = os.open(self.req_fifo_name, os.O_RDWR)

    # Now start it
    argv_str = "'%s'" % ' '.join(self.argv)
    try:
      # Set process group ID to the PID of the child.  Then we can kill all
      # processes in the group/tree at once.
      self.p = subprocess.Popen(self.argv, preexec_fn=os.setpgrp, **kwargs)
    except OSError, e:
      logging.error('Error running %s: %s (working dir %s)', argv_str, e,
          self.cwd)
      raise

    self.pid = self.p.pid  # for debugging/monitoring

    logging.info('Started %s (PID %d)', argv_str, self.pid)
    # We don't have anything to do with this log file -- only the child process
    # manages it.  TODO: Not sure why the unit tests fail with ValueError with
    # this code.  The Poly process should never try to write to this file; only
    # the child process should.
    #if self.log_fd:
    #  self.log_fd.close()

  def WorkingDirPath(self, path, legacy=False):
    """Get absolute paths for relative paths the child refers to."""
    return os.path.join(self.cwd, path)

  def _MaybeRemoveRequestFifo(self):
    if self.req_fifo_fd != -1:
      os.close(self.req_fifo_fd)

    if self.req_fifo_name:
      try:
        os.remove(self.req_fifo_name)
        logging.info('Removed request FIFO %r', self.req_fifo_name)
      except OSError, e:
        if e.errno != errno.ENOENT:
          log.warning('Error removing %s: %s', self.req_fifo_name, e)

  def _MaybeRemoveResponseFifo(self):
    """Close @response stream.."""
    if self.resp_fifo_fd != -1:
      os.close(self.resp_fifo_fd)

    if self.resp_fifo_name:
      try:
        os.remove(self.resp_fifo_name)
        logging.info('Removed response FIFO %r', self.resp_fifo_name)
      except OSError, e:
        if e.errno != errno.ENOENT:
          log.warning('Error removing %s: %s', self.resp_fifo_name, e)

  def SendRequest(self, req):
    """Send a request to the child process via its input stream."""
    # Request must be a single line.
    s = json.dumps(req) + '\n'
    os.write(self.req_fifo_fd, s)

  def RecvResponse(self):
    s = self.response_f.readline()
    # TODO: Parse error becomes dev error
    return json.loads(s)

  def SendHelloAndWait(self, timeout):
    """
    See if this child has entered its main loop by sending the PGI string
    '@cmd hello?'
    """
    start_time = time.time()

    # TODO: Unify request/response tnet/json with request/response.

    pgi_request = {'command': 'init'}

    logging.info('Python sending %r', pgi_request)
    self.SendRequest(pgi_request)  # list of "lines"

    # use hello timeout, not request timeout!
    try:
      response_str = self.response_f.readline()
      logging.info('GOT RESPONSE %r', response_str)
    except EOFError:
      elapsed = time.time() - start_time
      logging.error(
          'BROKEN: Received EOF instead of init response (%.2fs)', elapsed)
      return False

    response = json.loads(response_str)

    elapsed = time.time() - start_time
    if response.get('result') == 'ok':
      return True
    else:
      return False

  def Kill(self):
    """Send a kill signal to this process."""
    assert self.pid is not None, "Child wasn't Start()ed"
    try:
      # negate to send signal to process group
      os.kill(-self.pid, signal.SIGTERM)
    except OSError, e:
      logging.error('Error killing process -%d: %s', self.pid, e)
    logging.info('Sent signal to child -%d', self.pid)
    self._MaybeRemoveRequestFifo()
    self._MaybeRemoveResponseFifo()

  def Wait(self):
    """Wait for this process to exit."""
    child_pid, status = os.waitpid(self.pid, 0)
    if os.WIFSIGNALED(status):
      sig_num = os.WTERMSIG(status)
      logging.info('Child %s stopped by signal %s', child_pid, sig_num)
      return sig_num
    elif os.WIFEXITED(status):
      logging.info('Child %s stopped by exit()', child_pid)
      return 0
    else:
      raise AssertionError("Unknown status of child %s" % child_pid)


class ChildPool(object):
  """A queue of child processes for a given application.

  Take() a child to send it a request.  Return() it when you're done processing
  the response.
  """

  def __init__(self, replicas, timeout=None):
    self.children = Queue.Queue()
    for replica in replicas:
      self.children.put(replica)
    self.timeout = timeout

  def Take(self):
    """Grab a free process for the given app ID."""
    try:
      return self.children.get(block=True, timeout=self.timeout)
    except Queue.Empty, e:
      print e
      raise ReplicaTimeoutError(
          'Waited %.2f seconds for an applet replica' % self.timeout)

  def Return(self, process):
    return self.children.put(process)

  def TakeAndKillAll(self):
    # Take all the children first, so you don't kill a process that is in the
    # middle of a request.
    children = []
    while True:
      try:
        child = self.children.get(block=False)
      except Queue.Empty:
        break
      children.append(child)

    for c in children:
      c.Kill()
    for c in children:
      c.Wait()
