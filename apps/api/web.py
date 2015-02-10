#!/usr/bin/python
"""
web.py

A small web framework suitable for both REST services and simple web sites.

The model is very simple: Requests and responses are immutable values, and
handlers are functions.  This makes everything easy to test.

An app is defined by a list of (route, handler) pairs.

TODO:
  - enforce utf-8 -- it's "opinionated" in this way
    - Content-Type
    - json library gives you unicode objects; have to make sure you handle
      this.
    - set default encoding of Python interpreter?

- Could you do webpipe with this?
  - just need hanging get
  - I'm reusing the Python stdlib static file handler
"""

import cgi
import Cookie
import cStringIO
import httplib
import re
import json
import traceback


# WSGI headers.  We only support utf-8.
CONTENT_TYPE_TEXT = ('Content-Type', 'text/plain; charset=utf-8')
CONTENT_TYPE_HTML = ('Content-Type', 'text/html; charset=utf-8')
CONTENT_TYPE_JSON = ('Content-Type', 'application/json; charset=utf-8')


# TODO: Expose these errors to applications?  Right now you have them use
# ErrorResponse

class _BadRequest(Exception):
  """Raised by request parsing code."""
  pass


class _InternalServerError(Exception):
  """Raised by response generation code."""
  pass


class _AbstractRoute(object):
  """Match request metadata (method, path, etc.) against this pattern.

  The interface has affordance for both O(1) and O(n) handler lookup.
  """
  def __init__(self):
    pass

  def ConstKey(self):
    """Return a constant list of (method, path) we should match.
    
    Used for O(1) search."""
    return None

  def PathSuffix(self, method, path):
    """If HTTP method and path match, return a path suffix string, or False.

    Used for linear search -- O(n), where n is the number of routes.
    """
    return False

  def MatchObject(self, method, path):
    """If HTTP method and path match, return a regex match object, or False.

    Used for linear search.
    """
    return False  # doesn't match anything


class ConstRoute(_AbstractRoute):

  def __init__(self, method, path):
    self.method = method
    self.path = path

  def ConstKey(self):
    return (self.method, self.path)


class PrefixRoute(_AbstractRoute):

  def __init__(self, method, path_prefix):
    self.method = method
    # According to HTTP, foo and foo/ shouldn't be different.
    assert path_prefix.endswith('/'), "Prefix must end with /"
    self.path_prefix = path_prefix

  def PathSuffix(self, method, path):
    if method != self.method:
      return False
    x = self.path_prefix
    if path.startswith(x):
      return path[len(x) : ]
    return False


class RegexRoute(_AbstractRoute):

  def __init__(self, method, pattern, flags=0):
    self.method = method
    self.regex = re.compile(pattern, flags=flags)

  def MatchObject(self, method, path):
    if method != self.method:
      return False
    # Using match method.  User should add ^ and $.  ^ is not strictly
    # required, but $ is, so you should get in the habit.
    m = self.regex.match(path)
    if m:
      return m
    return False  # no match


class Request(object):
  """A parsed HTTP request.
  
  This is the object that request handlers see.  The info is derived from the
  WSGI request, but it is further parsed:

  query: query string parsed as dictionary; {} if no queries

  path_groups, path_groupdict:
    request path possibly parsed into regex groups (RegexRoute)
  path_suffix:
    request path with prefix removed (PrefixRoute)

  cookies: {string: Morsel} dict

  POST info:
    form: {str: str} dict
    files: {str: FieldStorage} dict
    json: Deserialized JSON POST (could be dict, list, number, etc.)
    raw_body: unparsed body, e.g. for HMAC validation

  Common headers:
    referer: Referer: header
    TODO: maybe look at node.js object

  raw_environ:  Raw WSGI request.
    In case you need something that's not available in another attribute.
    HTTP headers are HTTP_, HTTP_X, etc.
  """

  def __init__(self, environ, match, path_suffix):
    """
    Args:
      environ: original WSGI request object
      match: Regex match object, or None
      path_suffix: suffix of URL path, or None
    """
    # In case someone needs something special.  Like from the WSGI container.
    self.raw_environ = environ

    self.referer = environ.get('HTTP_REFERER')

    # Things matched out of the regex.
    if match:
      self.path_groups = match.groups()
      self.path_groupdict = match.groupdict()
    else:
      # Empty values
      self.path_groups = ()
      self.path_groupdict = {}

    self.path_suffix = path_suffix

    self.cookies = {}
    cookie_header = environ.get('HTTP_COOKIE')
    if cookie_header:
      c = Cookie.SimpleCookie()
      # NOTE: This method doesn't appear to throw exceptions?  It's very
      # liberal.
      c.load(cookie_header)

      # Use a plain dict; don't expose CookieLib interface to users
      for name, morsel in c.items():
        # morsels have values, expiration, path, etc.
        self.cookies[name] = morsel

    # QUERY_STRING may be absent.
    # https://www.python.org/dev/peps/pep-0333/
    self.query = {}
    query_string = environ.get('QUERY_STRING')
    if query_string:
      d = cgi.parse_qs(query_string)
      for k, v in d.iteritems():
        # We let the last one override previous ones
        self.query[k] = v[-1]

    if environ['REQUEST_METHOD'] == 'POST':
      # We need this workaround because wsgiref file object blocks on .read()
      # issued by cgi.FieldStorage.
      # We are reading the whole POST body into memory, but that's probably
      # inevitable.
      length = environ.get('CONTENT_LENGTH', '')

      # raw_body is a byte string; apps may validate HMAC signatures with it.
      self.raw_body = ''
      try:
        length = int(length)
      except ValueError:
        raise _BadRequest('Invalid content length %r' % length)
      else:
        # Must read the exact length
        if length > 0:
          self.raw_body = environ['wsgi.input'].read(length)

      content_type = environ.get('CONTENT_TYPE', '')

      self.json = None
      self.is_json_post = False  # "null" value could be None

      self.form = {}
      self.files = {}

      if not self.raw_body:  # empty body; .json and .form remain as default
        return

      # TODO: Do we need to parse the charset?
      # I think Firefox sends the same charset back, like this:
      # Content-Type: application-json; charset=UTF-8
      if content_type.startswith('application/json'):
        try:
          self.json = json.loads(self.raw_body)
          self.is_json_post = True
        except ValueError, e:
          msg = 'Error parsing JSON: %s\n\nREQUEST BODY:\n%s\n' % (
              e, self.raw_body)
          raise _BadRequest(msg)
        return  # DONE PARSING

      # If we read wsgi.input from the container's request, set it to the
      # in-memory version.
      body_file = cStringIO.StringIO(self.raw_body)
      environ['wsgi.input'] = body_file

      # This method is a little too magic, but it handles a lot of stuff,
      # including potential file uploads.  It handles:
      # - url-encoded form POST
      # - multi-part MIME form POST
      try:
        post_values = cgi.FieldStorage(
            fp=body_file, environ=environ, strict_parsing=True)
      except ValueError, e:
        raise _BadRequest('Error parsing POST body: %s' % e)

      if post_values:  # Need this for the empty case
        for key in post_values:
          field_storage = post_values[key]

          # NOTE: http://bugs.python.org/issue5340 -- exposed when upgrading
          # from Python 2.5 to Python 2.7.  Sometimes we get a single value;
          # sometimes a list.
          #
          # We are just blindly choosing the first one now.  What would be
          # nicer is to have request.params['hi'] and request.form['fo']
          if isinstance(field_storage, list):
            field_storage = field_storage[0]

          # Add uploaded files to self.files to preserve all FieldStorage
          # attributes.  Add simple values to self.form.
          if field_storage.filename:
            self.files[key] = field_storage
          else:  # regular value just has a string
            self.form[key] = field_storage.value


class _Response(object):
  """Abstract base class for HTTP response values."""

  def __init__(self, set_cookie=None):
    self.set_cookie = set_cookie  # type Cookie.SimpleCookie

  def BaseHeaders(self):
    h = []
    if self.set_cookie:
      # .output() adds Set-Cookie for you.  Suppress it.
      h.append(('Set-Cookie', self.set_cookie.output(header='')))
    return h

  def Status(self):
    raise NotImplementedError

  def Headers(self):
    raise NotImplementedError

  def Body(self):
    raise NotImplementedError


def _MakeStatus(code):
  return '%d %s' % (code, httplib.responses[code])


# Redirects
MOVED_PERMANENTLY = _MakeStatus(httplib.MOVED_PERMANENTLY)
TEMPORARY_REDIRECT = _MakeStatus(httplib.TEMPORARY_REDIRECT)

# Errors
BAD_REQUEST = _MakeStatus(httplib.BAD_REQUEST)  # 400
NOT_FOUND = _MakeStatus(httplib.NOT_FOUND)  # 404
INTERNAL_SERVER_ERROR = _MakeStatus(httplib.INTERNAL_SERVER_ERROR)  # 500


class RedirectResponse(_Response):
  """3xx."""

  def __init__(self, http_status, location, **kwargs):
    _Response.__init__(self, **kwargs)
    self.http_status = http_status
    self.location = location  # URL to redirect to

  def Status(self):
    return self.http_status

  def Headers(self):
    h = [CONTENT_TYPE_TEXT, ('Location', self.location)]
    return self.BaseHeaders() + h

  def Body(self):
    return 'Redirect to %s\n' % self.location


class ErrorResponse(_Response):
  """4xx or 5xx."""

  def __init__(self, http_status, message, **kwargs):
    _Response.__init__(self, **kwargs)
    self.http_status = http_status
    self.message = message

  def Status(self):
    return self.http_status

  def Headers(self):
    # No base headers because we don't want cookies for errors?
    return [CONTENT_TYPE_TEXT]

  def Body(self):
    return self.message + '\n'


class ContentResponse(_Response):
  """Real content."""

  def __init__(self, content_type, body, **kwargs):
    _Response.__init__(self, **kwargs)
    self.content_type = content_type
    self.body = body

  def Status(self):
    return '200 OK'

  def Headers(self):
    return self.BaseHeaders() + [self.content_type]

  def Body(self):
    return self.body


def PlainTextResponse(body, **kwargs):
  return ContentResponse(CONTENT_TYPE_TEXT, body, **kwargs)


def HtmlResponse(body, **kwargs):
  return ContentResponse(CONTENT_TYPE_HTML, body, **kwargs)


class JsonResponse(_Response):

  def __init__(self, dict_, **kwargs):
    # NOTE: awkward to use body=None
    _Response.__init__(self, **kwargs)
    self.dict_ = dict_

  def Status(self):
    return '200 OK'

  def Headers(self):
    return self.BaseHeaders() + [CONTENT_TYPE_JSON]

  def Body(self):
    # Pretty print it
    try:
      return json.dumps(self.dict_, indent=2) + '\n'
    except Exception, e:
      raise _InternalServerError('Error serializing JSON:\n\n%s\n' % e)


class App(object):
  """A WSGI web application."""

  def __init__(self, handlers):
    """
    Args:
      handlers: A list of (Route, Handler) pairs.
    """
    # TODO: Add options like:
    # error pages: custom error pages.  Or I guess you could return your own
    # ErrorResponse?
    # max_response_size -- for buffering

    self.dispatch = {}  # O(1) dispatch
    self.search = []  # O(n) search

    for route, handler in handlers:
      key = route.ConstKey()
      if key :
        self.dispatch[key] = handler
      else:
        # If it didn't return anything, it's something you need to search
        self.search.append((route, handler))

  def _GetHandler(self, method, path):
    # First do O(1) lookup
    h = self.dispatch.get((method, path))
    if h:
      return h, None, None

    # Now do O(n) search.
    # Note that the order of handlers matters!  All the non-const handlers are
    # checked in order.
    for route, handler in self.search:
      path_suffix = route.PathSuffix(method, path)
      if path_suffix is not False:  # IMPORTANT: empty string means match!
        return handler, None, path_suffix

      match = route.MatchObject(method, path)
      if match:
        return handler, match, None

    # No handler matched
    return None, None, None

  def __call__(self, environ, start_response):
    method = environ['REQUEST_METHOD'].upper()
    path = environ['PATH_INFO']

    handler, match, path_suffix = self._GetHandler(method, path)

    if not handler:
      start_response(NOT_FOUND, [CONTENT_TYPE_TEXT])
      yield 'No handler matched\n'
      return

    try:
      request = Request(environ, match, path_suffix)
    except _BadRequest, e:
      start_response(BAD_REQUEST, [CONTENT_TYPE_TEXT])
      yield e.args[0]
      yield '\n'
      return

    try:
      response = handler(request)
      # Don't call start_response before calling this, in case we have an
      # exception.
      body = response.Body()

      start_response(response.Status(), response.Headers())
      # The stdlib JSON library will gives you unicode values back; leading
      # JSON Template to expand into a unicode string.  WSGI requires a byte
      # string.
      if isinstance(body, unicode):
        yield body.encode('utf-8')
      else:
        yield body
    except _InternalServerError, e:
      start_response(INTERNAL_SERVER_ERROR, [CONTENT_TYPE_TEXT])
      yield e.args[0]
    except Exception, e:
      start_response(INTERNAL_SERVER_ERROR, [CONTENT_TYPE_TEXT])
      yield traceback.format_exc()
      #yield str(e) + '\n'

