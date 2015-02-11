# Copyright 2012 Google Inc.  All rights reserved.
# Use of this source code is governed by a BSD-style license that can be found
# in the COPYING file.

"""
child.py

Abstractions for child processes (a lower level that PGI applets).
"""

import errno
import json
import os
import Queue
import signal
import subprocess
import time

import errors
import file_io
import log


class Error(Exception):
  pass


def MakeDir(d):
  try:
    os.mkdir(d)
  except OSError, e:
    # OK if it exists
    if e.errno != errno.EEXIST:
      raise


class Child(object):
  """Encapsulates a child process (R interpreter, Python interpreter, etc.).

  Also manages any FIFOs needed to communicated with the process.
  """
  def __init__(
      self, argv,
      env=None, stop_signal=None,
      cwd=None,
      log_fd=None,
      output='stdout',
      timeout=3.0,
      template_data=None,
      pgi_format='tnet',
      ports={},  # name -> Port() instance
      ):
    """
    Args:
      argv: argument array
      env: environment dictionary for the process
      stop_signal: signal number to kill the process with
      log_fd: if specified, then stdout or stderr is redirect to this
        descriptor.
      timeout: timeout in seconds on output pipe reader
      template_data: additional data dictionary for DataDict()
      pgi_format: what format to use.  Used in SendHelloAndWait() now.
    """
    # By default, we kill with SIGKILL.  Applications might want to request
    # SIGTERM if they do something special.  TODO: Is SIGTERM better?  Then an
    # application can flush logs, etc.  That's probably why it's better to log
    # to stderr.
    self.argv = argv  # for DataDict
    self.env = env
    self.cwd = cwd
    self.stop_signal = stop_signal or signal.SIGKILL
    self.log_fd = log_fd

    # These values came from JSON; make them strings and not unicode
    self.timeout = timeout
    self.template_data = template_data or {}
    self.pgi_format = pgi_format

    self.req_fifo_name = None
    self.req_fifo_fd = -1

    # parallel to resp_pipe_fd.  TODO: Get rid of req_fifo_fd.  SendRequest
    # shouldn't have an "if" in it, but I don't want to disturb it now.
    self.req_pipe_fd = -1

    self.resp_fifo_name = None
    self.resp_fifo_fd = -1

    self.name = argv[0]  # for __str__

    # These attributes are unknown here and set by Start()
    self.pid = None
    self.p = None  # set by Start
    self.response_pipe = None  # don't know yet
    self.response_pipe2 = None  # don't know yet

    self.port_num = None  # port number
    if ports:
      # For now a single port?
      if len(ports) == 1:
        port_obj = ports.values()[0]
        port_num, ok = port_obj.GetPortNumber()
        if ok:
          self.port_num = port_num
          log.info('Picked port %d', port_num)

          # BUG(11/2013): This isn't propagated to bx tool!  Because that is
          # setting env as arg.

          self.env['PGI_PORT'] = str(port_num)
        else:
          # no free port, for now the app won't get what it wants it should
          # fail in some manner.
          log.error("Couldn't pick port")

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

    self.resp_fifo_name = os.path.join(self.cwd, 'response-fifo')
    self._MaybeRemoveResponseFifo()
    os.mkfifo(self.resp_fifo_name)
    # Need to use rw mode even though we only read.  This is to make the
    # open non-blocking, but the reads blocking.
    self.resp_fifo_fd = os.open(self.resp_fifo_name, os.O_RDWR)

    if self.log_fd:
      # If the response output is stdout, direct stderr to the debug log.  If
      # it's not (e.g. a named pipe), redirect both stdout and stderr.
      kwargs['stdout'] = self.log_fd
      kwargs['stderr'] = subprocess.STDOUT

    # Create request fifo if necessary
    self.req_fifo_name = None
    self.req_fifo_name = os.path.join(self.cwd, 'request-fifo')
    self._MaybeRemoveRequestFifo()
    os.mkfifo(self.req_fifo_name)
    #self.req_fifo_fd = os.open(self.req_fifo_name, os.O_RDWR|os.O_NONBLOCK)
    self.req_fifo_fd = os.open(self.req_fifo_name, os.O_RDWR)

    # Now start it
    argv_str = "'%s'" % ' '.join(self.argv)
    try:
      # set process group ID to the PID of the child.  Then we can kill all
      # processes in the group/tree at once.
      #
      # TODO: later we made need to protect against children that purposely
      # ignore SIGTERM.  Then we need a timeout on the wait(), check using
      # util.IsProcessRunning, and send SIGKILL.
      self.p = subprocess.Popen(self.argv, preexec_fn=os.setpgrp, **kwargs)
    except OSError, e:
      log.error('Error running %s: %s (working dir %s)', argv_str, e, self.cwd)
      raise
    self.pid = self.p.pid  # for debugging/monitoring
    log.info('Started %s (PID %d)', argv_str, self.pid)
    # We don't have anything to do with this log file -- only the child process
    # manages it.  TODO: Not sure why the unit tests fail with ValueError with
    # this code.  The Poly process should never try to write to this file; only
    # the child process should.
    #if self.log_fd:
    #  self.log_fd.close()

    # set req_pipe_fd -- has to be done after Popen call
    self.req_pipe_fd = self.req_fifo_fd

    self.resp_pipe_fd = self.resp_fifo_fd

    # Getting rid of PipeReader
    self.response_pipe2 = self.resp_pipe_fd
    self.response_f = os.fdopen(self.response_pipe2)

  def __str__(self):
    return '<Child %s %s>' % (self.pid, self.name)

  def __repr__(self):
    return self.__str__()

  def WorkingDirPath(self, path, legacy=False):
    """Get absolute paths for relative paths the child refers to."""
    return os.path.join(self.cwd, path)

  def _MaybeRemoveRequestFifo(self):
    if self.req_fifo_fd != -1:
      os.close(self.req_fifo_fd)

    if self.req_fifo_name:
      try:
        os.remove(self.req_fifo_name)
        log.info('Removed request FIFO %r', self.req_fifo_name)
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
        log.info('Removed response FIFO %r', self.resp_fifo_name)
      except OSError, e:
        if e.errno != errno.ENOENT:
          log.warning('Error removing %s: %s', self.resp_fifo_name, e)

  def OutputStream(self):
    return self.response_f

  def Write(self, byte_str):
    """
    Write a chunk of bytes to the input of this process (whether it's stdin or a
    named fifo).
    """
    os.write(self.req_pipe_fd, byte_str)

  def StubPage(self):
    if self.port_num:
      # TODO: We could return the port for EACH replicas.  But this is
      # secondary; the /NODE/processes page already has this info.
      body = "App uses port %d" % self.port_num
    else:
      body = "App doesn't serve HTTP (or isn't managed by Poly)"
    return {'response': util.HtmlResponse(body)}

  def SendRequest(self, req):
    """Send a request to the child process via its input stream."""
    try:
      assert self.req_fifo_fd != -1
      # NOTE: need a newline here
      s = json.dumps(req) + '\n'
      os.write(self.req_fifo_fd, s)
    except IOError, e:
      # TODO: If we get this broken pipe error, we should retry it instead of
      # raising an error.  We can keep this replica out of the queue, try
      # another one, and queue a work item to start a new replica to take its
      # place.  We will assume the process has died and we don't need to kill
      # it.
      if e.errno == errno.EPIPE:
        raise errors.AppletError('%s: %s' % (self, e))

  def SendHelloAndWait(self, timeout):
    """
    See if this child has entered its main loop by sending the PGI string
    '@cmd hello?'
    """
    start_time = time.time()

    # TODO: Unify request/response tnet/json with request/response.

    pgi_request = {'command': 'init'}

    log.info('Python sending %r', pgi_request)
    self.SendRequest(pgi_request)  # list of "lines"

    # use hello timeout, not request timeout!
    try:
      response_str = self.response_f.readline()
      log.info('GOT RESPONSE %r', response_str)
    except EOFError:
      elapsed = time.time() - start_time
      log.info('BROKEN: Received EOF instead of init response (%.2fs)', elapsed)
      return False
    except errors.TimeoutError, e:
      log.error('TimeoutError: %s', e)

      elapsed = time.time() - start_time
      log.info('Timed out after %.2fs', elapsed)

      # BUG: Need to kill the process here; otherwise we can end up with 2
      # copies of it
      return False

    if self.pgi_format == 'tnet':
      response = tnet.loads(response_str)
    elif self.pgi_format == 'json':
      #json_str = tnet.loads(response_str)
      #response = json.loads(json_str)
      response = json.loads(response_str)
    else:
      raise AssertionError(self.pgi_format)

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
      os.kill(-self.pid, self.stop_signal)
    except OSError, e:
      log.error('Error killing process -%d: %s', self.pid, e)
    log.info('Sent signal to child -%d', self.pid)
    self._MaybeRemoveRequestFifo()
    self._MaybeRemoveResponseFifo()

  def Wait(self):
    """Wait for this process to exit."""
    # TODO: If SIGTERM doesn't work after 10 seconds, try SIGQUIT?
    child_pid, status = os.waitpid(self.pid, 0)
    if os.WIFSIGNALED(status):
      sig_num = os.WTERMSIG(status)
      log.info('Child %s stopped by signal %s', child_pid, sig_num)
      return sig_num
    elif os.WIFEXITED(status):
      log.info('Child %s stopped by exit()', child_pid)
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
      raise errors.ReplicaTimeoutError(
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
