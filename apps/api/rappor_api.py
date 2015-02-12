#!/usr/bin/python
"""
rappor_api.py

TODO:
  - do import
    - ./rappor_api.py -e RAPPOR_SRC=SOME_DIR
    - and then source() that
    - analysis/R/analysis_lib, etc.
  - add CSV serialization, JSON -> CSV
  - add request ID
    - does that go in the framework?
    - request.counter?  Then R can log it
  - maybe test out plots
"""

import cgi
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
    POST /single-var <br/>

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


def ProcessHelper(pool, route_name, request):
  # Concurrency:
  # This will get called concurrently by different request threads

  # TODO: Add request ID
  logging.info('Waiting for child')
  child = pool.Take()
  try:
    # Construct JSON request from web.Request.
    req = {
        'route': route_name,
        'request': {
          'query': request.query
          }
        }
    logging.info('Sending %r', req)
    child.SendRequest(req)

    resp = child.RecvResponse()
    logging.info('RESP %r', resp)

  finally:
    logging.info('Returning child')
    pool.Return(child)

  # Caller may process JSON however they want
  return resp


class HealthHandler(object):
  """
  Tests if the R process is up by sending it a request and having it echo it
  back.

  TODO: Add startup, we should send a request to all threads?  Block until they
  wake up.
  """

  def __init__(self, pool):
    self.pool = pool

  def __call__(self, request):
    resp = ProcessHelper(self.pool, 'health', request)
    return web.PlainTextResponse(json.dumps(resp, indent=2))


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

  def __init__(self, pool):
    self.pool = pool

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

    resp = ProcessHelper(self.pool, 'dist', request)

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
      '--test', action='store_true', dest='test_mode', default=False,
      help='Batch test mode: serve one request and exit')
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
      ( web.ConstRoute('GET', '/_ah/health'), HealthHandler(pool)),
      ( web.ConstRoute('GET', '/sleep'),      SleepHandler(pool)),
      # TODO: Make it a POST
      ( web.ConstRoute('GET', '/dist'),       DistHandler(pool)),
      # JSON stats?
      # Logs
      # Work dir?
      ]

  return web.App(handlers)


def main(argv):
  (opts, argv) = Options().parse_args(argv)

  # TODO: Make this look better?
  logging.basicConfig(level=logging.INFO)

  # Construct a fake request, send it to the app, print response, and exit
  if opts.test_mode:
    pool = child.ChildPool([])
    # Only want 1 process for test mode
    opts.num_processes = 1
    InitPool(opts, pool)
    app = CreateApp(opts, pool)

    url = argv[1]
    if len(argv) >= 3:
      query = argv[2]
    else:
      query = ''

    wsgi_environ = {
        'REQUEST_METHOD': 'GET', 'PATH_INFO': url, 'QUERY_STRING': query}

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
