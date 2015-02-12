#!/usr/bin/python
"""
hello_web.py - A demo app exercising all the features of web.py.

Its tests implicitly tests the web framework.  This is more straightforward
than directly testing the framework.

TODO:
  - Fuzz this app
  - file parameters, etc.
"""

import cgi
import errno
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
# - regular form (add unicode by default, make sure you can round trip it)
# - AJAX JSON form
#   - does webpipe have the JS to copy?  or vanillajs
# - Go through all the input types, make sure you are using them and parsing
# them 
# http://www.w3schools.com/tags/tag_input.asp

HOME = """
<!DOCTYPE html>
<html>
  <head>
    <title>RAPPOR API Server</title>
  </head>
  <body>
    <h1><a href="https://github.com/google/rappor">RAPPOR</a> API Server</h1>

    <h3>Handlers</h3>

    <a href="/_ah/health">/_ah/health</a> <br/>
    <a href="/sleep">/sleep</a> <br/>
    POST /single-var <br/>
  </body>
</html>
"""

class HomeHandler(object):

  def __call__(self, request):
    return web.HtmlResponse(HOME)


def ProcessHelper(pool, route_name, request):
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
    # Concurrency:
    # Assume this gets called by different request threads
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


def Options():
  """Returns an option parser instance."""
  # TODO: where to get version number from?  Hook up to autodeploy?
  p = optparse.OptionParser('mayord.py [options]') #, version='0.1')

  p.add_option(
      '--tmp-dir', metavar='PATH', dest='tmp_dir', default='',
      help='Directory in which to store temporary request/response data.')
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
# - Write logs to PID-numbered files, in --log-dir
# - And then SERVE that dir with webutil (or App Engine)

def InitPool(num_processes, pool):

  for i in xrange(num_processes):
    logging.info('Starting child %d', i)

    work_dir = 'w%d' % i
    child.MakeDir(work_dir)

    c = child.Child(['../pages.R'],
        # TODO: Move this
        cwd=work_dir)
    c.Start()
    # Timeout: Do we need this?  I think we should just use a thread.
    c.SendHelloAndWait(10.0)

    print c
    pool.Return(c)


def CreateApp(opts, pool):
  # Go up two levels
  d = os.path.dirname
  static_dir = d(d(os.path.abspath(sys.argv[0])))

  handlers = [
      ( web.ConstRoute('GET', '/'),           HomeHandler()),
      ( web.ConstRoute('GET', '/_ah/health'), HealthHandler(pool)),
      ( web.ConstRoute('GET', '/sleep'),      SleepHandler(pool)),
      ]

  return web.App(handlers)


def main(argv):
  (opts, argv) = Options().parse_args(argv)

  # Make this olok better?
  logging.basicConfig(level=logging.INFO)

  if opts.test_mode:
    pool = child.ChildPool([])
    # Only want 1 process for test mode
    InitPool(1, pool)
    app = CreateApp(opts, pool)
    print app
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

  else:
    pool = child.ChildPool([])
    InitPool(opts.num_processes, pool)
    app = CreateApp(opts, pool)

    logging.info('Serving on port %d', opts.port)
    # Returns after Ctrl-C
    wsgiref_server.ServeForever(app, port=opts.port)

    logging.info('Killing child processes')
    pool.TakeAndKillAll()


if __name__ == '__main__':
  try:
    sys.exit(main(sys.argv))
  except RuntimeError, e:
    print >> sys.stderr, e.args[0]
    sys.exit(1)
