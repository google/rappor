#!/usr/bin/python
"""
rappor_api.py

TODO:
  - add request ID
    - does that go in the framework?
    - request.counter?  Then R can log it
  - maybe make this module into a library, and then App Engine has its own
    module which just calls CreateApp()
    - I think App Engine can't use flags
  - measure latency
    - expose it on /vars
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


class ChildWrapper(object):
  """Wraps a process pool.  Ensures the right route name is passed."""

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
      # Maybe it should be out_keys instead?

      for name in out_files:
        path = child.WorkingDirPath(name)
        try:
          with open(path) as f:
            app_resp[path] = f.read()
        except IOError, e:
          logging.error('Error reading %s: %s', path, e)

    finally:
      logging.info('Returning child')
      self.pool.Return(child)
      for path in to_remove:
        logging.info('Removing %s', path)
        try:
          os.unlink(path)
        except OSError, e:
          logging.error('Error reading %s: %s', path, e)

    return app_resp


class SleepHandler(object):
  """Sleep in R, to test parallelism."""

  def __init__(self, wrapper):
    self.wrapper = wrapper

  def __call__(self, request):
    app_req = {'query': request.query}
    resp = self.wrapper(app_req)
    return web.JsonResponse(resp)


class HealthHandler(object):
  """Tests if an R process is up by having it echo the request."""

  def __init__(self, wrapper):
    self.wrapper = wrapper

  def __call__(self, request):
    app_req = {'query': request.query}
    resp = self.wrapper(app_req)
    return web.JsonResponse(resp)


class ErrorHandler(object):
  """Tests unhandled exception."""

  def __init__(self, wrapper):
    self.wrapper = wrapper

  def __call__(self, request):
    app_req = {'query': request.query}
    resp = self.wrapper(app_req)
    return web.JsonResponse(resp)


def MakeLegacyParams(params):
  # TODO: input validation
  return {
      'k': params['numBits'],
      'h': params['numHashes'],
      'm': params['numCohorts'],
      'f': params['probPrr'],
      'p': params['probIrr0'],
      'q': params['probIrr1'],
  }


class DistHandler(object):
  """Distribution of single variable."""

  def __init__(self, state_dir, wrapper):
    self.state_dir = state_dir
    self.wrapper = wrapper

  def __call__(self, request):
    # TODO:
    # - maybe we should use @ as files?
    # - @params, @counts, @candidates -> @dist

    # or really, counts is just a matrix.  We can make it in memory
    # no csv files needed really
    # or maybe it's more debuggable

    # maybe time the serialization in R, to see if it's too slow
    # probably for

    print 'JSON'
    print request.json.keys()

    app_req = {}
    # first col of 'counts' matrix 
    app_req['num_reports'] = request.json['num_reports']
    # other columns
    app_req['sums'] = request.json['sums']

    # TODO: conver these
    app_req['params'] = MakeLegacyParams(request.json['params'])

    filename = request.json['candidates_file']

    # TODO: Add map cache here.  We may need to sync the file down for the R
    # process.
    if filename.endswith('.csv'):
      # This is a CSV file that can be passed directly to the R process.
      # It is immutable, so we can just pass the full path.
      candidates_path = os.path.join(self.state_dir, filename)
    else:
      # Allow JSON?  Convert it to CSV first
      candidates_path = None

    app_req['candidates_path'] = candidates_path
    logging.info('Candidates path: %s', candidates_path)

    resp = self.wrapper(app_req)

    # read CSV, convert to JSON

    return web.JsonResponse(resp)


def InitPool(opts, pool):
  rappor_src = os.environ['RAPPOR_SRC']  # required

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

    applet = os.path.join(rappor_src, 'apps/api/handlers.R')

    # NOTE: Can't start in a tmp dir, because of R imports.
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
      ( web.ConstRoute('GET', '/'),
        HomeHandler() ),

      ( web.ConstRoute('GET', '/sleep'),
        SleepHandler(ChildWrapper(pool, 'SleepHandler')) ),

      ( web.ConstRoute('GET', '/error'),
        ErrorHandler(ChildWrapper(pool, 'ErrorHandler')) ),

      ( web.ConstRoute('GET', '/_ah/health'),
        HealthHandler(ChildWrapper(pool, 'HealthHandler')) ),

      ( web.ConstRoute('POST', '/dist'),
        DistHandler(opts.state_dir, ChildWrapper(pool, 'DistHandler')) ),

      # JSON stats/vars?
      # Log dir
      # Work dir?
      ]

  return web.App(handlers)


def Options():
  """Returns an option parser instance."""
  p = optparse.OptionParser('mayord.py [options]')

  p.add_option(
      '--tmp-dir', metavar='PATH', dest='tmp_dir', default='/tmp',
      help='Store temporary request/response data in this directory.')
  p.add_option(
      '--log-dir', metavar='PATH', dest='log_dir',
      default=os.path.expanduser('~/rappor-api/logs'),
      help='Store child process logs in this directory')
  p.add_option(
      '--state-dir', metavar='PATH', dest='state_dir',
      default=os.path.expanduser('~/rappor-api/state'),
      help='Where state like candidates files are read from')

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


def main(argv):
  (opts, argv) = Options().parse_args(argv)

  # Make this look better?  How does App Engine deal with it?
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
