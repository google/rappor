#!/usr/bin/python
"""
rappor_api.py

TODO:
  - add CSV serialization, JSON -> CSV
  - add request ID
    - does that go in the framework?
    - request.counter?  Then R can log it
  - maybe test out plots
  - maybe make this module into a library, and then App Engine has its own
    module which just calls CreateApp()
"""

import cgi
import cStringIO
import logging
import json
import optparse
import os
import sys
import time

import child
import web
import wsgiref_server


# TODO:
# - Add flags
#   - not applicable in App Engine mode
# - Add process IDs

HOME = """
<!DOCTYPE html>
<html>
  <head>
    <title>RAPPOR API Server</title>
  </head>
  <body>
    <h1><a href="https://github.com/google/rappor">RAPPOR</a> API Server</h1>

    <h3>Handlers</h3>
    POST /dist - distribution of a single RAPPOR variable<br/>

    <h3>Debug</h3>

    <a href="/_ah/health">/_ah/health</a> <br/>
    <a href="/_ah/health2">/_ah/health2</a> <br/>
    <a href="/sleep">/sleep</a> <br/>
    <a href="/sleep?seconds=1">/sleep?seconds=1</a> <br/>
    <a href="/vars">/vars</a> <br/>
    <a href="/logs">/logs</a> <br/>
  </body>
</html>
"""

class HomeHandler(object):

  def __call__(self, request):
    return web.HtmlResponse(HOME)


class ChildHandler(object):
  """Abstract base class which lets you communicate with a child process.

  Handlers which need a child process will generally hold one of these.  Then
  they can do custom serialization.
  """
  def __init__(self, pool, route_name, wrapper):
    self.pool = pool
    self.route_name = route_name
    self.wrapper = wrapper  # handler that takes a child

  def __call__(self, request):
    logging.info('Waiting for child')

    # NOTE: another way to express this would be with context manager
    #
    # with GetChild(self.pool) as child:
    #
    child = self.pool.Take()
    try:
      app_req = self.wrapper.MakeRequest(child, request)
      req_line = {
          'route': self.route_name,  # protocol.R dispatch
          'request': app_req,
          }

      logging.info('Sending %r', req_line)
      child.SendRequest(req_line)

      # TODO: Handle dev error properly.  That shouldn't go to the sub handler.
      resp_line = child.RecvResponse()
      logging.info('Received %r', resp_line)

      response = self.wrapper.MakeResponse(child, resp_line)
    finally:
      logging.info('Returning child')
      self.pool.Return(child)
    return response


class ProcWrap(object):

  def __init__(self, pool, route_name):
    self.pool = pool
    self.route_name = route_name

  def __call__(self, app_req, in_files=None, out_files=None):
    in_files = in_files or {}
    out_files = out_files or []

    child = self.pool.Take()
    try:
      # TODO:
      # - request ID?
      to_remove = []
      for name, contents in in_files.iteritems():
        path = child.WorkingDirPath(name)
        with open(path, 'w') as f:
          f.write(contents)
        to_remove.append(path)

      req_line = {
          'route': self.route_name,  # protocol.R dispatch
          'request': app_req,
          }
      logging.info('Sending %r', req_line)
      child.SendRequest(req_line)

      resp_line = child.RecvResponse()
      # TODO: Handle dev error properly.  That shouldn't be returned
      app_resp = resp_line

      logging.info('Received %r', resp_line)

      # TODO: Read app_resp instead for names of files to read?
      # 'dist': 'dist.csv'
      #
      # Maybe it should be out_keys instead?

      for name in out_files:
        path = child.WorkingDirPath(name)
        with open(path) as f:
          app_resp[path] = f.read()

    finally:
      logging.info('Returning child')
      self.pool.Return(child)
      for path in to_remove:
        logging.info('Removing %s', path)
        os.unlink(path)

    return app_resp


# TODO: Delete
def ProcessHelper(pool, route_name, request):
  # Concurrency:
  # This will get called concurrently by different request threads

  # TODO: Add request ID
  logging.info('Waiting for child')
  child = pool.Take()

  # Write files into the working path / tmp dir
  tmp_dir = child.WorkingDirPath('params.csv')
  logging.info('PARAMS %s', tmp_dir)

  try:
    # Construct single-line JSON request from web.Request.
    # The protocol.R loop sees the top level data.  Handler sees 'request'
    # level stuff.  TODO: rename to 'handler'?
    req_line = {
        'route': route_name,
        'request': {
            'query': request.query
            }
        }
    logging.info('Sending %r', req_line)
    child.SendRequest(req_line)

    resp = child.RecvResponse()
    logging.info('RESP %r', resp)

  finally:
    logging.info('Returning child')
    pool.Return(child)

  # Caller may process JSON however they want
  return resp


# TODO: Delete
class HealthHandler(object):
  """
  Tests if the R process is up by sending it a request and having it echo it
  back.

  TODO: Add startup, we should send a request to all threads?  Block until they
  wake up.
  """
  def __init__(self, wrapper):
    self.wrapper = wrapper

  def __call__(self, request):
    app_req = {'query': request.query}
    resp = self.wrapper(app_req)
    return web.JsonResponse(resp)


class HealthWrapper(object):
  """Wrapper for health request that passes through to R.

  NOTE: We're only checking one R process!  Could check more than one.
  """
  def MakeRequest(self, child, request):
    """Given a web.Request, make a R JSON line."""
    # Need query params
    return {'query': request.query}

  def MakeResponse(self, child, response):
    """Given an R JSON line, make a web.Response."""
    return web.JsonResponse(response)


class DistWrapper(object):
  """Wrapper for health request that passes through to R.

  NOTE: We're only checking one R process!  Could check more than one.
  """
  def MakeRequest(self, child, request):
    """Given a web.Request, make a R JSON line."""

    print '!!', request.json

    p = child.WorkingDirPath('params.csv')
    c = child.WorkingDirPath('counts.csv')
    m = child.WorkingDirPath('map.csv')

    with open(p, 'w') as f:
      f.write('a,b\n')
      f.write('1,2\n')

    # TODO:
    # - request.json.params -> CSV
    # - request.json.counts -> CSV
    # - request.json.candidates -> CSV
    #
    # Put pointers to them

    # Need query params
    return {'query': request.query}

  def MakeResponse(self, child, response):
    """Given an R JSON line, make a web.Response."""

    # Read dist.csv -> put in response JSON
    #
    # Delete it

    # Also delete params, counts, candidates
    # Where to save it?  Maybe you should also get the request?
    # or state

    d = child.WorkingDirPath('dist.csv')
    with open(d) as f:
      dist = f.read()

    response['dist'] = dist

    p = child.WorkingDirPath('params.csv')
    c = child.WorkingDirPath('counts.csv')
    m = child.WorkingDirPath('map.csv')

    return web.JsonResponse(response)


class SleepHandler(object):
  """
  Tests if the R process is up by sending it a request and having it echo it
  back.

  TODO: Add startup, we should send a request to all threads?  Block until they
  wake up.
  """

  def __init__(self, pool):
    self.pool = pool

  def __call__(self, request):
    resp = ProcessHelper(self.pool, 'sleep', request)
    return web.JsonResponse(resp)


class DistHandler(object):
  """Distribution of single variable."""

  def __init__(self, wrapper):
    self.wrapper = wrapper

  def __call__(self, request):
    # TODO:
    # - process request.json
    # - write to CSV
    # - put filenames in the request
    # - maybe we should use @ as files?
    # - @params, @counts, @candidates -> @dist

    # or really, counts is just a matrix.  We can make it in memory
    # no csv files needed really
    # or maybe it's more debuggable

    print 'JSON'
    print request.json.keys()

    params = """
a,b
1,2
"""
    app_req = request.json
    resp = self.wrapper(
        app_req,
        in_files={'params.csv': params},
        out_files=['dist.csv'])

    # read CSV, convert to JSON

    return web.JsonResponse(resp)


def Options():
  """Returns an option parser instance."""
  # TODO: where to get version number from?  Hook up to autodeploy?
  p = optparse.OptionParser('mayord.py [options]') #, version='0.1')

  p.add_option(
      '--tmp-dir', metavar='PATH', dest='tmp_dir', default='/tmp',
      help='Store temporary request/response data in this directory.')
  p.add_option(
      '--log-dir', metavar='PATH', dest='log_dir', default='',
      help='Store child process logs in this directory')

  p.add_option(
      '--port', metavar='NUM', dest='port', type=int, default=8500,
      help='Port to serve HTTP on')
  p.add_option(
      '--num-processes', metavar='NUM', dest='num_processes', type=int,
      default=2,
      help='Number of concurrent R processes to use (e.g. set to # of CPUs).')
  p.add_option(
      '--test-get', action='store_true', dest='test_get', default=False,
      help="Serve GET request and exit.  e.g. 'rappor-api --test-get URL QUERY'")
  p.add_option(
      '--test-post', action='store_true', dest='test_post', default=False,
      help="Serve POST request and exit.  e.g. 'rappor-api --test-post URL' "
           'JSON body should be on stdin.')
  # Shared secret?
  return p


# TODO:
# - And then SERVE log dir with webutil (or App Engine)

def InitPool(opts, pool):

  for i in xrange(opts.num_processes):
    logging.info('Starting child %d', i)

    tmp_dir = os.path.join(opts.tmp_dir, 'w%d' % i)
    child.MakeDirs(tmp_dir)

    if opts.log_dir:
      # Make a directory per server invocation.
      log_subdir = os.path.join(opts.log_dir, 'rappor-api-%d' % os.getpid())
      child.MakeDirs(log_subdir)
      filename = os.path.join(log_subdir, '%d.log' % i)
      f = open(filename, 'w')
    else:
      filename = None
      f = None

    rappor_src = os.environ['RAPPOR_SRC']  # required
    applet = os.path.join(rappor_src, 'apps/api/handlers.R')

    c = child.Child([applet], cwd=tmp_dir, log_fd=f)
    c.Start()

    if filename:
      logging.info('Child %s logging to %s', c, filename)
    logging.info('Child %s started in %s', c, tmp_dir)

    # Timeout: Do we need this?  I think we should just use a thread.
    start_time = time.time()
    if not c.SendHelloAndWait(10.0):
      raise RuntimeError('Failed to initialize child %s' % c)
    logging.info(
        'Took %.3f seconds to initialize child', time.time() - start_time)

    pool.Return(c)


def CreateApp(opts, pool):
  # Go up two levels
  d = os.path.dirname
  static_dir = d(d(os.path.abspath(sys.argv[0])))

  handlers = [
      ( web.ConstRoute('GET', '/'),           HomeHandler()),
      ( web.ConstRoute('GET', '/sleep'),      SleepHandler(pool)),

      ( web.ConstRoute('GET', '/_ah/health'),
        HealthHandler(ProcWrap(pool, 'health')) ),

      ( web.ConstRoute('POST', '/dist'),
        DistHandler(ProcWrap(pool, 'dist')) ),

      ( web.ConstRoute('GET', '/_ah/health2'),
        ChildHandler(pool, 'health', HealthWrapper()) ),

      ( web.ConstRoute('POST', '/dist-new'),
        ChildHandler(pool, 'dist', DistWrapper()) ),
      # JSON stats/vars?
      # Logs
      # Work dir?
      ]

  return web.App(handlers)


def main(argv):
  (opts, argv) = Options().parse_args(argv)

  # TODO: Make this look better?
  logging.basicConfig(level=logging.INFO)

  # Construct a fake request, send it to the app, print response, and exit
  if opts.test_get or opts.test_post:
    pool = child.ChildPool([])
    opts.num_processes = 1  # Only 1 process for test mode
    InitPool(opts, pool)
    app = CreateApp(opts, pool)

    url = argv[1]
    if len(argv) >= 3:
      query = argv[2]
    else:
      query = ''

    if opts.test_get:
      wsgi_environ = {
          'REQUEST_METHOD': 'GET', 'PATH_INFO': url, 'QUERY_STRING': query
          }
    elif opts.test_post:
      body = sys.stdin.read()  # request body on stdin
      content_length = len(body)
      wsgi_environ = {
          'REQUEST_METHOD': 'POST',
          'PATH_INFO': url,
          'CONTENT_TYPE': 'application/json',
          'CONTENT_LENGTH': content_length,
          'wsgi.input': cStringIO.StringIO(body),
          }
    else:
      raise AssertionError

    def start_response(status, headers):
      print 'STATUS', status
      print 'HEADERS', headers

    try:
      for chunk in app(wsgi_environ, start_response):
        print chunk
    finally:
      pool.TakeAndKillAll()

  # Start serving
  else:
    pool = child.ChildPool([])
    InitPool(opts, pool)
    app = CreateApp(opts, pool)

    logging.info('Serving on port %d', opts.port)
    # Returns after Ctrl-C
    wsgiref_server.ServeForever(app, port=opts.port)

    logging.info('Killing child processes')
    pool.TakeAndKillAll()


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, e.args[0]
    sys.exit(1)
