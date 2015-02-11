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
import re
import optparse
import os
import sys
import time

import log
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
    POST /single-var <br/>
  </body>
</html>
"""

class HomeHandler(object):

  def __call__(self, request):
    return web.HtmlResponse(HOME)


class HealthHandler(object):
  """
  Tests if the R process is up by sending it a request and having it echo it
  back.

  TODO: Add startup, we should send a request to all threads?  Block until they
  wake up.
  """

  def __init__(self, pool):
    self.pool = pool

    # TODO:
    # - Block until all processes have been initialized
    # - Why does the R process not die when you hit Ctrl-C?  Should be in the
    # same process group?

    c = child.Child(
        ['./pages.R'], input='fifo', output='fifo',
        # TODO: Move this
        cwd='.',
        pgi_version=2,
        pgi_format='json',
        )
    c.Start()
    # Timeout: Do we need this?  I think we should just use a thread.
    c.SendHelloAndWait(10.0)

    print c
    self.pool.Return(c)

  def __call__(self, request):
    # Concurrency:
    # Assume this gets called by different request threads

    child = self.pool.Take()

    # For testing concurrency
    # TODO: Do in R?
    seconds = request.query.get('sleepSeconds', '0')
    seconds = int(seconds)
    seconds = min(seconds, 10)
    if seconds:
      log.info('Sleeping %d seconds', seconds)
      time.sleep(seconds)

    # NOTE: Need newline here
    req = {"foo": "bar"}
    child.SendRequest(req)

    f = child.OutputStream()
    log.info('out: %r', f)
    resp = f.readline()
    log.info('RESP %r', resp)

    self.pool.Return(child)

    return web.PlainTextResponse(
        'RESPONSE: %r\n\n(sleep %d)' % (resp, seconds))


class OopsHandler(object):

  def __call__(self, request):
    # NameError
    foo


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


def CreateApp(opts):
         
  # Go up two levels
  d = os.path.dirname
  static_dir = d(d(os.path.abspath(sys.argv[0])))

  pool = child.ChildPool([])

  handlers = [
      ( web.ConstRoute('GET', '/_ah/health'), HealthHandler(pool)),

      ( web.ConstRoute('GET', '/'),           HomeHandler()),

      ( web.ConstRoute('GET', '/oops'), OopsHandler()),
      ]

  return web.App(handlers)


def main(argv):
  (opts, argv) = Options().parse_args(argv)

  app = CreateApp(opts)

  if opts.test_mode:
    print app
  else:
    log.info('Serving on port %d', opts.port)
    wsgiref_server.ServeForever(app, port=opts.port)


if __name__ == '__main__':
  try:
    sys.exit(main(sys.argv))
  except RuntimeError, e:
    print >> sys.stderr, e.args[0]
    sys.exit(1)
