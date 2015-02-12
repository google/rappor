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
import re
import optparse
import os
import sys
import time

import web
import wsgiref_server

import child


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

    # For testing concurrency
    # TODO: Do in R?
    seconds = request.query.get('sleepSeconds', '0')
    seconds = int(seconds)
    seconds = min(seconds, 10)
    if seconds:
      logging.info('Sleeping %d seconds', seconds)
      time.sleep(seconds)

    # TODO: How to dispatch on route?
    req = {'route': route_name, 'request': {"a": 3}}
    logging.info('Sending %r', req)
    child.SendRequest(req)

    resp = child.RecvResponse()
    logging.info('RESP %r', resp)

  finally:
    logging.info('Returning child')
    pool.Return(child)

  return web.PlainTextResponse(
      'RESPONSE: %r\n\n(sleep %d)' % (resp, seconds))


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
    return ProcessHelper(self.pool, 'health', request)


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
    return ProcessHelper(self.pool, 'sleep', request)


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


def InitPool(num_processes, pool):
  # TODO: Keep track of PIDs?
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
      ( web.ConstRoute('GET', '/_ah/health'), HealthHandler(pool)),

      ( web.ConstRoute('GET', '/'),           HomeHandler()),

      ( web.ConstRoute('GET', '/sleep'), SleepHandler(pool)),
      ]

  return web.App(handlers)


def main(argv):
  (opts, argv) = Options().parse_args(argv)

  # Make this olok better?
  logging.basicConfig(level=logging.INFO)

  pool = child.ChildPool([])
  InitPool(opts.num_processes, pool)

  app = CreateApp(opts, pool)

  if opts.test_mode:
    print app
  else:
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
