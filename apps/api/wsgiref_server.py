#!/usr/bin/python -S
"""
Development WSGI server.

NOTE: Python stdlib gives you an HTTP 1.0 server!  Don't use in production.
"""

import SocketServer
import sys

import logging
from wsgiref import simple_server


class ThreadedWSGIServer(SocketServer.ThreadingMixIn, simple_server.WSGIServer):
  pass


# TODO:
# - If debug=True is passed, add WSGI exception middleware.  It can will show
# the stack trace in the HTTP response.

def ServeForever(app, single_thread=False, port=8000):
  """Start a WSGI server container with the given WSGI app."""

  # TODO: Come up with a nicer name for the app
  logging.info('Serving %s on port %d' % (app, port))

  if single_thread:
    server_class = simple_server.WSGIServer
    logging.info('Using single-threaded %s', server_class)
  else:
    server_class = ThreadedWSGIServer
    logging.info('Using multi-threaded %s', server_class)

  server = simple_server.make_server('', port, app, server_class=server_class)
  try:
    server.serve_forever()
  except KeyboardInterrupt:
    logging.info('Interrupted')
