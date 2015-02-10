#!/usr/bin/python
#
# Copyright 2012 Google Inc.  All rights reserved.
# Use of this source code is governed by a BSD-style license that can be found
# in the COPYING file.

"""
errors.py

Put common exceptions here.  They can be raised from different modules and still
have the same identity.
"""

__author__ = 'Andy Chu'


class _MessageError(Exception):
  """
  Raised when there is an error writing a request to an applet or reading a
  response from it.  This is also raised if the applet doesn't obey the PGI
  protocol.
  """
  def __init__(self, text):
    Exception.__init__(self)
    self.text = text

  def __str__(self):
    return self.text


class AppletError(_MessageError):
  """
  Caught at the top level of app_server.py.  Results in a 500.

  TODO: Get rid of most usages of this.  It has been conflated with PgiError in
  the code as well.
  """
  pass


class PgiError(_MessageError):
  """
  DEPRECATED: PGI 1 only.  This description is inaccurate, as I also started
  using it to report protocol errors.

  The applet used the PGI protocol to report an error that should be logged.

  For example, this is used for unhandled exceptions in applets.  The
  applet will print

  @error until:@@END@@
  Stack Trace
  @@END@@

  These kinds of errors are turned into 500 Internal Server Error.
  The .text attribute is filled with the "payload".
  """

class TimeoutError(_MessageError):
  """Read() from the applet timed out."""


class ReplicaTimeoutError(_MessageError):
  """
  The queue for an applet replica remained empty for a longer than the timeout
  period.
  """

class EmptyResponse(Exception):
  """Raised when an applet returns no output."""


class UsageError(Exception):
  """Raised when the server is invoked incorrectly."""


class StartupError(Exception):
  """Invalid state detected on startup."""


class UpdateError(_MessageError):
  """Errors that occur during the update process.  Will be shown to the user."""


class ConfigError(UpdateError):
  """Raised when either poly_config fails or we have an in-server error.

  APP configs are only loaded in the background thread in production mode; thus
  they are classified as UpdateErrors and can be shown in the web interface.

  In dev mode, we load the APP file in the request thread.  There is a global
  except: in app_server.py to catch ConfigError.
  """


class HttpError(_MessageError):
  """Raise this exception when you want an HTTP error.

  The Poly code raises this exceptions, and then they are "formatted" at a
  higher level.
  """
  def __init__(self, status, text):
    """
    Args:
      status: integer for HTTP status code, e.g. 400, 404, 500, 503, etc.
      text: Descriptive text to show to the user
    """
    _MessageError.__init__(self, text)
    self.status = status  # Used by app_server.py


class HttpBadRequest(HttpError):
  """400 Bad Request"""
  def __init__(self, text):
    HttpError.__init__(self, 400, text)


class HttpUnauthorized(Exception):
  """401 Unauthorized

  This is handled differently than other HTTP exceptions.
  """
  def __init__(self, realm=None):
    self.realm = realm


class HttpForbidden(HttpError):
  """403 Forbidden"""
  def __init__(self, text):
    HttpError.__init__(self, 403, text)


class HttpNotFound(HttpError):
  """404 Not Found"""
  def __init__(self, text):
    HttpError.__init__(self, 404, text)


class HttpRequestEntityTooLarge(HttpError):
  """413 Request Entity Too Large"""
  def __init__(self, text):
    HttpError.__init__(self, 413, text)


class HttpInternalServerError(HttpError):

  def __init__(self, text):
    HttpError.__init__(self, 500, text)


class HttpServiceUnavailable(HttpError):

  def __init__(self, text):
    HttpError.__init__(self, 503, text)
