#!/usr/bin/python
#
# Copyright 2011 Google Inc.  All rights reserved.
# Use of this source code is governed by a BSD-style license that can be found
# in the COPYING file.

"""app_types.py

Code for starting/communicating with different kinds of child processes.
"""

from __future__ import with_statement


__author__ = 'Andy Chu'

import errno
import os

#import app_types_old
#import child
#import env
#import errors
#import file_io
#import log
#import mime_types
#import protocol
#import util
#import vfs
#
#json = env.Module('json')
#tnet = env.Module('tnet')
#jsontemplate = env.Module('jsontemplate')


class ResponseTooBig(RuntimeError):
  """Raised when a response is above the configured size limit."""
  pass


class _SizeLimiter(object):
  """This exists so we can keep track of which read put us over the edge."""

  def __init__(self, max_pgi_response_size, chunk_size):
    self.max_pgi_response_size = max_pgi_response_size
    self.bytes_left = max_pgi_response_size
    self.chunk_size = chunk_size
    self.history = []

  def Withdraw(self, num_bytes):
    self.history.append(num_bytes)
    self.bytes_left -= num_bytes
    if self.bytes_left < 0:
      raise ResponseTooBig('exceeded %d bytes (%s)' % (
          self.max_pgi_response_size, self.history))


def _ReadDiskFile(path, size_limiter):
  """Reads a file from disk in chunks and returns its contents."""

  log.info('Reading response from %r', path)
  # NOTE: When we switch to an event-driven server, this has to be changed
  # since it will block.
  contents = ''

  chunk_size = size_limiter.chunk_size
  try:
    with open(path) as f:
      f = open(path)
      while True:
        chunk = f.read(chunk_size)
        if not chunk:
          break
        size_limiter.Withdraw(len(chunk))
        contents += chunk
  except IOError:
    # caught by top level app_server
    raise errors.PgiError("Can't find response file %r" % path)

  return contents


def _ReadReferences(root, child, size_limiter):
  """
  MUTATES root by dereferencing names starting with &.

  If we have a file "bar.txt" with the contents "Hello", then

  &foo: "bar.txt"
  ->
  foo: "Hello"

  Raises:
    ResponseTooBig: if we read too much from the app.
  """
  for n, v in root.iteritems():
    if n.startswith('&'):
      new_name = n[1:]
      if isinstance(v, list):
        new = []
        for item in v:
          path = child.WorkingDirPath(item)
          contents = _ReadDiskFile(path, size_limiter)
          new.append(contents)
        del root[n]
        root[new_name] = new
      else:
        path = child.WorkingDirPath(v)
        contents = _ReadDiskFile(path, size_limiter)
        del root[n]
        root[new_name] = contents
      continue  # & should only preface string or list of strings

    # Recursve
    if isinstance(v, dict):
      _ReadReferences(v, child, size_limiter)
    elif isinstance(v, list):
      for item in v:
        _ReadReferences(item, child, size_limiter)
  return root


_CHUNK_SIZE = 1024 * 1024

def _ReadFiles(app_response, child, size_limiter):
  """MUTATES app_response.

  TODO: This *could* be stage.  (We would have to pass a reference to the child
  though).

  One issue is that all existing stages are pure CPU, while reading files from
  disk is pure I/O, so it doesn't quite fit.  Defer until we have an
  event-driven design.
  """
  raw_body_filename = app_response.get('raw_body_filename')
  if raw_body_filename:
    path = child.WorkingDirPath(raw_body_filename)
    contents = _ReadDiskFile(path, size_limiter)
    app_response['raw_body'] = contents
    del app_response['raw_body_filename']  # Don't need this any more

  # NOTE: This is undocumented, perhaps only for PGI 1
  body_data_filename = app_response.get('body_data_filename')
  if body_data_filename and not raw_body_filename:  # only one is allowed
    path = child.WorkingDirPath(body_data_filename)
    contents = _ReadDiskFile(path, size_limiter)
    try:
      body_data = tnet.loads(contents)
    except ValueError, e:
      raise errors.PgiError("Invalid TNET data: %s" % e)
    app_response['body_data'] = body_data
    del app_response['body_data_filename']  # Don't need this any more

  # Walk through and read stuff with &
  body_data_refs = app_response.pop('body_data_refs', None)
  if body_data_refs is not None:
    body_data = _ReadReferences(body_data_refs, child, size_limiter)
    app_response['body_data'] = body_data

  # For symmetry, also expand message_refs with &.
  message_refs = app_response.pop('message_refs', None)
  if message_refs is not None:
    message = _ReadReferences(message_refs, child, size_limiter)
    app_response['message'] = message


def _ProcessResponse(child, on_request_served, on_request_error,
                     pgi_format='tnet',
                     max_pgi_response_size=10*1000*1000,
                     chunk_size=_CHUNK_SIZE):
  """Returns response in a "normalized" format.

  Args:
    child: Child() instance
    on_request_served: call this on success
    on_request_error: call this on an error
    pgi_version: int, 1 or 2
    max_pgi_response_size: max number of bytes for response
    chunk_size: read chunk size (for testing)

  Returns:
    A dictionary with status/headers/body fields
    PGI 1/2 can return 'body'

  See poly/routes.py _PostProcessResponse.
  """
  log.info('Reading PGI 2 response from %s', child)
  # TODO: Limit to max_pgi_response_size.
  # Maybe change to tnet.read(), so we can count how big the string is.  We
  # could read a 1MB tnet response.  And then we have 9MB left for any
  # included files.
  try:
    response_str = tnet.read(child.OutputStream(),
                             max_length=max_pgi_response_size)
  except errors.TimeoutError, e:
    # Kill and restart applet on timeout
    on_request_error()
    raise
  except ValueError, e:
    log.error('Fatal exception reading from response pipe: %s', e)
    # Kill and restart when response is too big or invalid TNET.  # If the
    # applet tried to # send a big request, then there could still be a ton of
    # data in the pipe.  # It's better to just kill it and restart.
    on_request_error()
    raise

  if pgi_format == 'tnet':
    try:
      response = tnet.loads(response_str)
    except ValueError:
      # For now we don't have a better error message to add.  This will happen
      # if the PGI library does something bad.
      raise
  elif pgi_format == 'json':
    json_str = tnet.loads(response_str)
    response = json.loads(json_str)
  else:
    raise AssertionError

  # We read it OK.  Still could get bad response, but no need to kill.
  on_request_served()

  if not isinstance(response, dict):
    raise errors.PgiError(
        "Expected PGI 2 response to be a dictionary, got %r" % response)

  # TODO: This is premature in the pipeline.  We could have gotten response_pb
  # instead.
  app_response = response.get('response')

  if app_response is not None:  # dev error, etc.
    if not isinstance(app_response, dict):
      raise errors.PgiError(
          "Expected app response to be a dictionary, got %r" % app_response)

    size_limiter = _SizeLimiter(max_pgi_response_size, chunk_size)
    size_limiter.Withdraw(len(response_str))
    try:
      _ReadFiles(app_response, child, size_limiter)
    except ResponseTooBig, e:
      log.error('Response from app is too big: %s', e)
      raise errors.PgiError(str(e))

  # default 200 status, etc. is set in poly/routes.py
  return response


class Applet(object):
  """Base class for all apps."""

  def HandleRequest(self, request):
    pass

  def DataDict(self):
    return {}


class InProcessApplet(Applet):
  """An app that lives in the same process as the AppServer WSGI application.

  NOTE: This currently isn't different than Applet.
  """

  def HandleRequest(self, request):
    pass

  def DataDict(self):
    # TODO: Return self.name?  e.g. for HomeApplet and such
    return {}


#LISTING_TEMPLATE = jsontemplate.Template("""
#{.repeated section @}
#  <a href="{@|htmltag}">{@|html}</a> <br/>
#{.or}
#  (none)  {# TODO: Better error message}
#{.end}
#""")

class StaticApplet(InProcessApplet):
  """An applet that serves static files.

  NOTE: This does disk IO, so when we switch to an event driven model, it might
  have to be handled with thread still.
  """

  def __init__(self, base_dir, index_filename=None):
    self.base_dir = base_dir
    self.index_filename = index_filename

  def HandleRequest(self, request):
    # TODO: Allow user to override Content-Type with StaticRoute
    path = request['PATH']

    # TODO: should we have a check for redirecting /index.html -> / ?

    # First try the file path, then the dir path.
    file_path = None
    dir_path = None

    is_url_dir = (path == '' or path.endswith('/'))
    ext = None
    if is_url_dir:
      # Try this file first.
      if self.index_filename:
        file_path = util.SafeJoin(self.base_dir, path, self.index_filename)
      dir_path = util.SafeJoin(self.base_dir, path)
    else:
      file_path = util.SafeJoin(self.base_dir, path)

    # Guess path from the extension of the file on DISK, which may be different
    # than the URL "filename" because of index_filename.
    content_type = None
    if file_path:
      _, ext = os.path.splitext(file_path)
      if ext:
        content_type = mime_types.GuessFromExtension(ext[1:])  # Could return None

    if not content_type:
      # TODO: Could guess application/octet by sniffing the file
      content_type = 'text/plain'

    log.info('Static app serving %s', file_path)

    if file_path:
      try:
        f = open(file_path)
      except IOError, e:
        if e.errno == errno.EISDIR:
          # Do trailing slash redirect since we got a URL "file" that's actually
          # a directory on disk.
          last_part = os.path.basename(path)
          status, headers, body = util.MovedPermanently(last_part + '/')
          return status, headers, body  # EARLY RETURN
      except OSError, e:
        pass
      else:
        # EARLY RETURN
        return 200, [('Content-Type', content_type)], file_io.DiskFileContents(f)

    if dir_path:
      # Try to list the directory
      try:
        entries = os.listdir(dir_path)
      except OSError:
        pass
      else:
        # Append trailing slash to directories, so relative URLs work.
        paths = []
        for e in entries:
          if os.path.isdir(os.path.join(dir_path, e)):
            e += '/'
          paths.append(e)
        body = LISTING_TEMPLATE.expand(paths)
        return 200, [('Content-Type', 'text/html; charset=UTF-8')], body

    # Not found.
    p = file_path or dir_path  # the thing that wasn't found
    return 404, [('Content-Type', 'text/plain')], ['%s not found\n' % p]


def _FeedJournal(child, journal):
  """
  Protocol:

  Server writes:

  1. a command record
  2. however many result records
  3. A sentinel, which is the empty string: '0:,'

  Then the applet responds with a status:

  {result: ok, detail: ...}

  Hm, this protocol might need more acknowledgement from the app.
  """
  # Write bytes
  #print journal

  name = journal.name
  log.info('Feeding journal %s', name)
  pgi_request = {
      'command': 'load-journal',
      'request': {'name': name},
      }
  log.info('Writing load-journal')
  child.Write(tnet.dumps(pgi_request))
  for b in journal.ReadJournal():
    log.info('record %r', b)
    assert isinstance(b, str)
    child.Write(tnet.dumps(b))

  child.Write('0:,')  # SENTINEL

  print 'WAITING'
  pgi_response = tnet.load(child.OutputStream())

  result = pgi_response.get('result')
  if result != 'ok':
    raise RuntimeError("load-journal didn't return 'ok': %r" % pgi_response)

  print 'RESULT', result
  # protocol:
  # -> {"command": "load-journal", "name": "urls"}
  # <- {"result": "ok", "detail": ""}
  # -> record


class PgiApplet(Applet):
  """Base class for out-of-process PGI Apps.

  Each instance represents an executable provided by the user, which will have 0
  or more replicas.

  By default the the server writes requests to stdin of the child process, and
  reads responses from stdout.  responses are written to stdout.

  These can be replaced with FIFOs instead.  The FIFOs are created by the
  server.
  """
  def __init__(self,
               runtime,
               bin_tree,  # binary subtree for this applet
               app_id=None,  # app that this applet belongs to
               in_tree_ref=None,
               name=None,
               executable=None,
               argv=[],  # list

               env={},
               request_format=None,
               pgi_format='tnet',  # for unit tests
               num_replicas=-1,  # default from server
               timeout=-1,  # default from server
               hello_timeout=-1,  # default from server
               tags=[],
               input='stdin',
               output='stdout',
               ports={},  # name -> Port() instance
               container=None,
               bundles={},
               remotes={},
               journals={},
               pgi_version=1,  # default in schema
               ):
    """
    Args:
      runtime: 'applet' section of runtime options, .e.g runtime.applet

      See Applet schema in poly/poly_schemas.py.
    """
    Applet.__init__(self)
    self.runtime = runtime
    self.bin_tree = bin_tree
    self.app_id = app_id
    self.in_tree_ref = in_tree_ref
    self.name = name  # used by META/, log dir, etc.
    self.executable = executable
    self.argv = argv

    self.more_env = env
    self.request_format = request_format
    self.pgi_format = pgi_format
    self.tags = tags

    self.input = input
    self.output = output

    self.ports = ports
    self.container = container

    self.bundles = bundles
    self.remotes = remotes
    self.journals = journals
    self.pgi_version = pgi_version
    # END ARG assignment


    # TODO: This has too many members.
    # Collapse like this:
    # self.runtime...
    # self.spec - AppletSpec perhaps
    #    config_loader should create the spec
    # And then internal state is:
    #   or self.state -> mutable state
    #   self.children
    #   log_dir, tmp_root, work_tre
    #   ready_queue, etc.

    # global settings
    self.lazy_replica_count = 0  # how many replicas started so far in lazy mode

    # set by PrepareApplet:
    self.applet_work_tree = None
    self.log_dir = None
    self.tmp_root = None  # used for display only

    self.children = []
    # This counter is only used for the argument to InitChild.  It starts out at
    # 0.  The user will request N replicas; then it will be N.  When applets are
    # replaced (after timing out, etc.), it will become N+1, N+2, etc.
    self.replica_counter = 0

    self.update_queue = runtime.update_queue

    a = runtime.applet_options  # temp
    self.dev_mode = a.dev_mode
    self.lazy_mode = a.lazy_mode

    # These 3 options can be set in the applet, or they can be set by flags from
    # applet_options.
    if num_replicas == -1:
      self.num_replicas = a.default_replicas
    else:
      self.num_replicas = num_replicas  # used by META/

    if timeout == -1:
      self.timeout = a.default_timeout
    else:
      self.timeout = timeout

    if hello_timeout == -1:
      self.hello_timeout = a.hello_timeout
    else:
      self.hello_timeout = hello_timeout

    # Init pool now that we know the timeout.  In hard dev mode, we kill and
    # restart a child every time.  There is no ready queue.
    self.ready_queue = None
    if self.dev_mode != 'hard':
      self.ready_queue = child.ChildPool([], self.timeout)

    self._set_dirs = False

    self.launcher = self._DetermineLauncher()

  def Executable(self):
    """Used by config.ChangePermissions() and below."""
    return self.executable

  def __repr__(self):
    return '<PgiApplet %s>' % self.Executable()

  # TODO: Possibly unify DataDict and MetaData.  MetaData is called from
  # config.PgiApplets(), which is called from meta.MetaApplet.
  def DataDict(self):
    d = {
        'type': 'APPLET',
        'name': self.name,
        'children': [c.DataDict() for c in self.children],
        }
    
    # TODO(BUG): If --using-tool is not set, we shouldn't use this.
    # Maybe the container needs a runtime flag or something.
    c = self.container
    if c:
      d['container'] = {
          'name': c.name,
          'local_path': c.local_path,
          }

    return d

  def MetaData(self):
    """Returns a dictionary of data for the META/ page."""
    prefix = self.tmp_root
    if prefix.endswith('/'):
      prefix = prefix[:-1]

    # The relative working dir will be used to construct a link to dir in
    # /HOST/files/tmp-root/
    if self.children:
      replicas = []
      for (i, c) in enumerate(self.children):
        # Get relative paths from absolute paths, since we know it's in tmp_root
        assert c.cwd.startswith(prefix)
        working_dir = c.cwd[len(prefix)+1:]

        replicas.append({'num': i, 'pid': c.pid, 'working_dir': working_dir})
    else:
      # dummy data for dev mode / testing
      replicas = [
          {'num': i, 'pid': i, 'working_dir': 'dir%d' % i}
          for i in xrange(self.num_replicas)]

    # Return a list of (replica number, PID).
    return {
        'name': self.name,
        'replicas': replicas,
        }

  def Journals(self):
    """Return a dictionary of name -> Journal instance."""
    return self.journals

  def FeedJournals(self):
    """
    Feed journals to all processes.
    """
    # This IO from disk to a pipe.  I guess it has to be done in a thread.
    # TODO: feed them in order of declaration in the app file?  This is in
    # dictionary order, which isn't specified.
    for j in self.journals.itervalues():
      # TODO: ensure that there's only on replica of this applet?
      child = self.children[0]
      _FeedJournal(child, j)
    # read result from child process output.
    # {result: OK}
    # {result: failed} -- the app can return an error explicitly, e.g. it
    #   doesn't want to accept this many records, or it had an error parsing a
    #   record, etc.  The new code no longer understands a record writen by an
    #   older version of the app.
    #   invalid journal name.
    # {dev_error} -- unhandled exception

    # Success
    return True

  def PrepareApplet(self, working_dir, log_dir, tmp_root):
    """Make directories for an applet.

    Some directories are common to all replicas of an applet.  We also make
    directories for a specific replica, and append to self.children.

    If the applet runs in a container, then dirs will be mounted into the
    container.

    NOTE: This is called from ConfigLoader.Load, which is run in a
    background thread (usually?), so it's OK to do disk operations here.  It is
    NOT called from ConfigLoader.Find(), because that generally reuses
    prev_state.

    TODO: Name is misleading!  PrepareApplet shouldn't also create children.

    Args:
      working_dir: Directory where all of this app's files should live
      log_dir: May be None to indicate that application logs are not redirected
      tmp_root: --tmp-root flag; used for display only.  This is a (distant)
        parent of the working_dir.
    """
    # See above
    if self._set_dirs:
      return
    self._set_dirs = True

    # applet working dir is a subdir of the app work dir
    self.applet_work_tree = vfs.Tree(working_dir)
    self.log_dir = log_dir
    self.tmp_root = tmp_root

    # Make a directory for all logs for this applet
    if self.log_dir:
      util.MakeDirs(self.log_dir)

    # Initialize children now that self.working_dir is set
    # TODO: This initialization sequence sucks, need to make a config.Init() and
    # a PgiApplet.Init().
    for i in xrange(self.num_replicas):
      self.children.append(self.InitChild(i))

    # TODO: This line doesn't appear to have test coverage!
    self.replica_counter = self.num_replicas

  def _DetermineLauncher(self):
    """Called in constructor; we use this launcher for all replicas."""

    allow_free_apps = self.runtime.allow_free_apps

    if self.container:
      # If the user specifies a container attribute, use the UsingLauncher.
      # This is probably on its way out.  Apps generally shouldn't need
      # hard-coded images, since it's less efficient than using Basis.
      u = self.runtime.using_launcher
      if u:
        return u
      else:
        # Allow running apps outside containers.
        if allow_free_apps:
          return self.runtime.free_launcher
        else:
          raise errors.UpdateError(
              "Got an applet %r with a container %s, but server wasn't "
              "configured with --using-tool" % (self.name, self.container.name))

    path = self.bin_tree.Path(self.executable)
    if os.path.isdir(path):
      # If executable is a directory, use the bx launcher.
      b = self.runtime.bx_launcher
      if b:
        return b
      else:
        raise errors.UpdateError(
            "Got an applet %r with an app bundle, but server wasn't configured "
            "with --bx-tool" % self.name)

    if self.runtime.allow_free_apps:
      return self.runtime.free_launcher

    else:
      # UpdateError is shown to user.  User doesn't need to know about about
      # --allow-free-apps; that's for the administrator
      raise errors.UpdateError(
          "Server can't run applet %r because it's a plain executable, not an "
          "app bundle." % self.executable)

  def InitChild(self, replica_num):
    """Make directories for a particular child, and instantiate it.

    This function is called for each replica.

    Returns:
       child.Child instance
    """
    # Call stack:
    #   config.PrepareApp()
    #   for each applet:
    #     applet.PrepareApplet()
    #     for each child process:
    #       InitChild()

    # TODO: Do we need a separate applet spec in the config?  Are there "startup
    # options" for an app, and runtime options?
    applet_spec = util.Record(
        name=self.name,
        executable=self.executable,
        argv=self.argv,
        more_env=self.more_env,
        input=self.input,
        output=self.output,
        timeout=self.timeout,
        pgi_version=self.pgi_version,
        pgi_format=self.pgi_format,
        ports=self.ports,

        bin_tree=self.bin_tree,
        work_tree=self.applet_work_tree,  # working dirs

        # this is a subdir of a parent in "runtime", could go in there.
        in_tree_ref=self.in_tree_ref,  # uploaded files tree
        bundles=self.bundles,
        remotes=self.remotes,
        log_dir=self.log_dir,
        app_id=self.app_id,
        options=self.runtime.applet_options)

    # TODO(1/14):
    # We initialize child.Child instances here, with their command line.
    # Perhaps in the supervisor case, we should return a StubChild instead.
    # - StubChild has the SPID, not the PID?
    # - StubChild responds to HasIO() and StubPage()?

    return self.launcher.InitChild(
        applet_spec, self.container, replica_num)

  def log_info(self, msg, *args):
    msg = '%s: ' + msg
    args = (self.name,) + args
    log.app_info(self.app_id, msg, *args)

  def log_error(self, msg, *args):
    msg = '%s: ' + msg
    args = (self.name,) + args
    log.app_error(self.app_id, msg, *args)

  def StartAndAddChild(self):
    """Called from adjust-replicas task in background thread."""
    self.replica_counter += 1
    ch = self.InitChild(self.replica_counter)
    # Add it here so we can see it in /NODE/processes/
    self.children.append(ch)
    ch.Start()
    success = ch.SendHelloAndWait(self.hello_timeout)
    if success:
      self.AddGoodChild(ch)
      log.app_info(self.app_id, 'Added replica for applet %s', self.name)
    else:
      # TODO: Here we just forget about the task.  It may be desirable to retry
      # a limited number of times?  This probably requires user intervension.
      log.app_error(self.app_id,
          '%s: Restarted replica was unresponsive', self.name)
    return success

  def AddGoodChild(self, child):
    """Call this after the hello ping succeeds."""
    self.ready_queue.Return(child)

  def MaybeStartChildren(self):
    """Start child processes and return a list of them.

    If this is not called, then we're in "dev mode".
    """
    if self.dev_mode == 'hard':
      return True  # Don't start applets eagerly

    assert self.num_replicas > 0, (
        'num_replicas is %s, SetGlobalFlags most likely not called' %
        self.num_replicas)

    # We don't start children up front in lazy mode.  Done in HandleRequest
    if self.lazy_mode:
      return []

    for ch in self.children:
      ch.Start()
    return False

  def SoftCleanup(self):
    """Clean up child processes if we started them."""
    if self.ready_queue:
      self.ready_queue.TakeAndKillAll()

  def HandleRequest(self, request):
    """
    Args:
      request: PGI request as a dictionary
    """
    lines = protocol.MakeRequestLines(request, self.request_format,
                                      self.pgi_format)
    if not lines:
      raise errors.PgiError('Bad request %s' % request)

    # Obtain a child process by starting it or getting it from the pool
    if self.dev_mode == 'hard':
      log.info('Starting child in hard dev mode')
      self.replica_counter += 1
      child = self.InitChild(self.replica_counter)
      child.Start()
    elif self.lazy_mode:
      assert self.ready_queue
      # TODO: Currently there are is only a single thread in lazy mode; consider
      # just having one app
      if self.lazy_replica_count < self.num_replicas:
        log.info('Starting child in lazy mode (%d < %d)',
            self.lazy_replica_count, self.num_replicas)
        child = self.InitChild(self.lazy_replica_count)
        child.Start()
        self.log_info('Waiting for response')
        child.SendHelloAndWait(self.hello_timeout)
        self.log_info('Adding good child')
        self.AddGoodChild(child)
        self.lazy_replica_count += 1
      child = self.ready_queue.Take()
    else:
      child = self.ready_queue.Take()

    # TODO: After we have the child, we can put request-dependent temp files in
    # child.WorkingPath()?  The Route() will generate a series off files on disk
    # like 001.paper.pdf and 002.data.csv.  These names are guaranteed to be
    # globally unique.  Then the app can simply use the same name, presented as
    # "body_filename" to the PGI app.
    #
    # before Return(), we can remove that filename.

    log.app_info(self.app_id, '(%s) sending %s to child %d', self.name,
                 util.Truncate(repr(lines)), child.pid)

    if not child.HasIO():
      # NOTE: This may return the port of a random process.
      # We could just use Applet.input/output as a test, /NODE/processes already
      # has that info.
      log.app_info(self.app_id, 'Returning child %s to pool', child)
      self.ready_queue.Return(child)
      return child.StubPage()

    child.SendRequest(lines)

    # CALLBACK DEFINITIONS ----------------------------------------------------

    # Set up the function to called AFTER the WSGI server has consumed all of
    # the output
    def KillChild():
      log.info('Killing child %s in dev mode', child)
      child.Kill()
      child.Wait()

    # If it timeouts, etc. we should kill it
    def KillChildAndRestart():
      # TODO: Should Kill/Wait() be in the background too?  Wait() may never
      # return if the child isn't responding to SIGTERM.
      log.app_warning(self.app_id, 'Killing child %s after error', child)
      child.Kill()
      child.Wait()

      # BUG/TODO: The AdjustReplicasHandler in poly/updater.py is defunct!  It
      # was never ported to the new stages.py framework.  So, for example, when
      # a response payload is too large, the applet will get killed, but never
      # restarted.  It's a better design to have something besides Poly restart
      # it.
      log.app_warning(self.app_id, 'Queueing restart of applet %s', self.name)
      task = {
          'action': 'adjust-replicas',
          'app_id': self.app_id,
          'applet_id': self.name,
          # Number to add
          'num_add': 1,
          }
      self.update_queue.put([task])

    def ReturnChild():
      log.app_info(self.app_id, 'Returning child %s to pool', child)
      self.ready_queue.Return(child)

    # ... END CALLBACK DEFINITIONS.

    if self.ready_queue:
      on_request_served = ReturnChild
      on_request_error = KillChildAndRestart
    else:
      if self.dev_mode == 'hard':
        on_request_served = KillChild
        on_request_error = KillChild
      else:
        # lazy mode: same as regular mode for now
        on_request_served = ReturnChild
        on_request_error = KillChildAndRestart
    m = self.runtime.applet_options.max_pgi_response_size
    if self.pgi_version == 2:
      return _ProcessResponse(
          child, on_request_served, on_request_error, pgi_format=self.pgi_format,
          max_pgi_response_size=m)
    else:
      return app_types_old._ProcessResponseOld(
          child, on_request_served, on_request_error)
