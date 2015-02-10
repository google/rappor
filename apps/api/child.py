# Copyright 2012 Google Inc.  All rights reserved.
# Use of this source code is governed by a BSD-style license that can be found
# in the COPYING file.

"""
child.py

Abstractions for child processes (a lower level that PGI applets).
"""

import errno
import os
import Queue
import signal
import subprocess
import time

import errors
import env
import file_io
import log
import util

json = env.Module('json')
tnet = env.Module('tnet')


class Error(Exception):
  pass


_WAITING = 0  # waiting to start
_STARTING = 1  # waiting for ping response
_READY = 2  # ping response sent; ready to serve
_STOPPED = 3

# NOTE: updater.py has a _STOPPING state, but we don't have one here.  That
# could be surface in in TakeAndKillAll.
_BROKEN = 4


def _StateDisplay(state):
  """Returns string, CSS class."""
  if state == _WAITING:
    return 'WAITING', 'normal'
  elif state == _STARTING:
    # STARTED 4 seconds ago
    return 'STARTING', 'normal'
  elif state == _READY:
    # READY in 3.2s
    return 'READY', 'good'
  elif state == _STOPPED:
    return 'STOPPED', 'normal'
  elif state == _BROKEN:
    # BROKEN Could not load app config
    return 'BROKEN', 'bad'
  else:
    raise AssertionError('Invalid child state %s' % state)


class Child(object):
  """Encapsulates a child process (R interpreter, Python interpreter, etc.).

  Also manages any FIFOs needed to communicated with the process.
  """
  def __init__(
      self, argv,
      env=None, stop_signal=None,
      cwd=None,
      log_fd=None,
      input='stdin',
      output='stdout',
      timeout=3.0,
      template_data=None,
      pgi_version=None,
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
      input: specifies request input (stdin or fifo).  If None, then requests
        aren't handled at all.  It is assumed that the child bound its own port.
      output: specifies response output (stdout stderr or fifo).
        TODO: stderr not a good idea because not buffered?
      timeout: timeout in seconds on output pipe reader
      template_data: additional data dictionary for DataDict()
      pgi_version: protocol version 1 or 2
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
    self.input = input.encode('utf-8')
    self.output = output.encode('utf-8')
    self.timeout = timeout
    self.template_data = template_data or {}
    self.pgi_version = pgi_version
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

    # Normally processes start right away.  But if there is a "startup group"
    # then the apps in that group start serially.
    self._ChangeStatus(_WAITING)

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

  def _ChangeStatus(self, state, note=None):
    self.status = (state, time.time(), note)

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

    if self.output == 'stdout' or self.output == 'stderr':
      kwargs[self.output] = subprocess.PIPE
    elif self.output == 'fifo':
      self.resp_fifo_name = util.SafeJoin(self.cwd, 'response-fifo')
      self._MaybeRemoveResponseFifo()
      os.mkfifo(self.resp_fifo_name)
      # Need to use rw mode even though we only read.  This is to make the
      # open non-blocking, but the reads blocking.
      self.resp_fifo_fd = os.open(self.resp_fifo_name, os.O_RDWR)
    elif self.output == 'none':
      pass
    else:
      raise AssertionError(self.output)

    if self.log_fd:
      # If the response output is stdout, direct stderr to the debug log.  If
      # it's not (e.g. a named pipe), redirect both stdout and stderr.
      if self.output == 'stdout':
        kwargs['stderr'] = self.log_fd
      elif self.output == 'stderr':
        kwargs['stdout'] = self.log_fd
      else:
        kwargs['stdout'] = self.log_fd
        kwargs['stderr'] = subprocess.STDOUT

    # Create request fifo if necessary
    self.req_fifo_name = None
    if self.input == 'fifo':
      self.req_fifo_name = util.SafeJoin(self.cwd, 'request-fifo')
      self._MaybeRemoveRequestFifo()
      os.mkfifo(self.req_fifo_name)
      self.req_fifo_fd = os.open(self.req_fifo_name, os.O_RDWR|os.O_NONBLOCK)
    elif self.input == 'stdin':
      # Requests go on stdin
      kwargs['stdin'] = subprocess.PIPE
    elif self.input == 'none':
      pass
    else:
      raise AssertionError(self.input)

    # Now start it
    argv_str = util.ArgvString(self.argv)
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
    if self.input == 'fifo':
      self.req_pipe_fd = self.req_fifo_fd
    elif self.input == 'stdin':
      self.req_pipe_fd = self.p.stdin.fileno()
    elif self.input == 'none':
      self.req_pipe_fd = None
    else:
      raise AssertionError(self.input)

    # Now set resp_pipe_fd for callers to read from
    if self.output == 'stdout':
      self.resp_pipe_fd = self.p.stdout.fileno()  # PUBLIC
    elif self.output == 'stderr':
      self.resp_pipe_fd = self.p.stderr.fileno()
    elif self.output == 'fifo':
      self.resp_pipe_fd = self.resp_fifo_fd
    elif self.output == 'none':
      self.resp_pipe_fd = None
    else:
      # Should have been checked by the schema
      assert self.resp_pipe_fd is not None, 'Invalid output %r' % self.output

    # The unused one will remain None
    if self.pgi_version == 1:
      self.response_pipe = file_io.PipeReader(
          self.resp_pipe_fd, timeout=self.timeout)
    elif self.pgi_version == 2:
      self.response_pipe2 = file_io.PipeReader2(
          self.resp_pipe_fd, timeout=self.timeout)

    self._ChangeStatus(_STARTING)

  def __str__(self):
    return '<Child %s %s>' % (self.pid, self.name)

  def __repr__(self):
    return self.__str__()

  def DataDict(self):
    status = self.status  # be extra sure reads are consistent
    state, timestamp, note = status
    state_str, css_class = _StateDisplay(state)

    data = {
        'type': 'PROCESS',
        'pid': self.pid,
        'argv': self.argv,
        'state': state_str,
        'css_class': css_class,
        'time': timestamp,
        'note': note,
        'port': self.port_num,
        }
    data.update(self.template_data)
    return data

  def WorkingDirPath(self, path, legacy=False):
    """Get absolute paths for relative paths the child refers to."""
    # TODO: remove this when PGI 1 is removed.
    if legacy:
      return os.path.join(self.cwd, path)
    return util.SafeJoin(self.cwd, path)

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
    if self.pgi_version == 1:
      return self.response_pipe
    if self.pgi_version == 2:
      return self.response_pipe2
    raise AssertionError('Invalid pgi version: %r', self.pgi_version)

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

  def HasIO(self):
    return self.input != 'none' and self.output != 'none'

  def SendRequest(self, request_lines):
    """Send a request to the child process via its input stream."""
    if not self.HasIO():
      raise AssertionError("Should not send request without IO.")

    try:
      # TODO: Use self.Write()
      if self.req_fifo_fd != -1:
        for line in request_lines:
          os.write(self.req_fifo_fd, line)
      else:
        for line in request_lines:
          self.p.stdin.write(line)
        self.p.stdin.flush()
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
    # Disable when there is no input/output.  TODO: We should be have
    # user-defined probes in this case.  Or maybe just send GET / by default.
    if not self.HasIO():
      self._ChangeStatus(_READY, 'socket')
      return True

    start_time = time.time()

    if self.pgi_version == 2:
      # TODO: Unify request/response tnet/json with request/response.

      pgi_request = {'command': 'init'}

      if self.pgi_format == 'tnet':
        req_str = tnet.dumps(pgi_request)
      elif self.pgi_format == 'json':
        json_str = json.dumps(pgi_request)
        req_str = tnet.dump_line(json_str)
      else:
        raise AssertionError(self.pgi_format)

      self.SendRequest([req_str])  # list of "lines"

      # use hello timeout, not request timeout!
      hello_pipe = file_io.PipeReader2(self.resp_pipe_fd, timeout=timeout)
      try:
        response_str = tnet.read(hello_pipe)
      except EOFError:
        elapsed = time.time() - start_time
        self._ChangeStatus(_BROKEN,
            'Received EOF instead of init response (%.2fs)' % elapsed)
        return False
      except errors.TimeoutError, e:
        elapsed = time.time() - start_time
        self._ChangeStatus(_BROKEN, 'Timed out after %.2fs' % elapsed)
        # BUG: Need to kill the process here; otherwise we can end up with 2
        # copies of it
        return False

      if self.pgi_format == 'tnet':
        response = tnet.loads(response_str)
      elif self.pgi_format == 'json':
        json_str = tnet.loads(response_str)
        response = json.loads(json_str)
      else:
        raise AssertionError(self.pgi_format)

      elapsed = time.time() - start_time
      if response.get('result') == 'ok':
        self._ChangeStatus(_READY, 'in %.2fs (PGI 2)' % elapsed)
        return True
      else:
        self._ChangeStatus(_BROKEN, 'Invalid reply %s' % response)
        return False

    # -- PGI 2 never gets past here --

    self.SendRequest(['@cmd hello?\n'])
    out = file_io.PipeReader(self.resp_pipe_fd, timeout=timeout)
    try:
      line = out.ReadLine()
    except errors.TimeoutError, e:  # TODO: expand this list of errors?
      elapsed = time.time() - start_time
      self._ChangeStatus(_BROKEN, 'Timed out after %.2fs' % elapsed)

      # BUG: Need to kill the process here; otherwise we can end up with 2
      # copies of it

      return False
    else:
      line = line.lstrip()
      if not line.startswith('hello'):
        # UpdateError so we can show this on the web interface
        raise errors.UpdateError(
            'Process %d responded with %r instead of "hello"' %
            (self.pid, line))
      elapsed = time.time() - start_time
      self._ChangeStatus(_READY, 'in %.2fs' % elapsed)
      return True

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

  def SetStopped(self):
    # It would be nice to know how long it took to stop the process, but the
    # signals are all sent in parallel.
    self._ChangeStatus(_STOPPED)


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
      c.SetStopped()
