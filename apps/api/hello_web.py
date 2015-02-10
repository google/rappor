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
import Cookie
import re
import optparse
import os
import sys
    

import web
#import webutil
import wsgiref_server

import app_types
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
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.8.3/jquery.min.js">
    </script>
  </head>

  <body>
    <h1>Hello web.py</h1>

    <h3>GET Handlers</h3>

    <a href="/_ah/health">/_ah/health</a> <br/>
    <a href="/text">/text</a> <br/>
    <a href="/json">/json</a> <br/>
    <a href="/redirect">/redirect</a> <br/>
    <a href="/set-cookie">/set-cookie</a> <br/>
    <a href="/users">/users</a> <br/>
    <a href="/users/">/users/</a> <br/>
    <a href="/users/bob">/users/bob</a> <br/>
    <a href="/static/">/static/</a> <br/>

    <h3>Simple Form (urlencoded)</h3>

      <form action="/urlencoded-post" method="POST" >
        <table>
          <tr>
            <td>Name</td>
            <td><input type="text" name="name" value="" /></td>
          </tr>
          <tr>
            <td>Adult</td>
            <td><input type="checkbox" name="adult" value="1" /></td>
          </tr>
          <tr>
            <td>sex</td>
            <td><input type="radio" name="male" value="M" /></td>
          </tr>
          <tr>
            <td></td>
            <td><input type="radio" name="female" value="F" /></td>
          </tr>
          <tr>
            <td></td>
            <td><input type="submit" /></td>
          </tr>
        </table>
      </form>

    <h3>File Upload Form (multipart/form-data)</h3>

      <form action="/multipart-post" method="POST" enctype="multipart/form-data">
        <table>
          <tr>
            <td>textname</td>
            <td><input type="text" name="textname" value="" /></td>
          </tr>
          <tr>
            <td>file1</td>
            <td><input type="file" name="file1" value="" /></td>
          </tr>
          <tr>
            <td>file2</td>
            <td><input type="file" name="file2" value="" /></td>
          </tr>
          <tr>
            <td></td>
            <td><input type="submit" /></td>
          </tr>
        </table>
      </form>

    <h3>JSON Post with AJAX</h3>

      <!-- TODO: Make form button -->

      <form action="">
        <textarea id="user-json"></textarea>
        <table>
          <tr>
            <td></td>
            <td><input type="submit" id="json-post" /></td>
          </tr>
          <tr>
            <td>Response</td>
            <td>
              <pre id="response"></pre>
            </td>
          </tr>
          <tr>
            <td>AJAX Status:</td>
            <td>
              <div id="ajax-status"></div>
            </td>
          </tr>

        </table>
      </form>

    <h3>User Error</h3>

      <a href="/users/invalid-user">/users/invalid-user</a> <br/>
      <a href="/does-not-exist-ZZZ">/does-not-exist-ZZZ</a> <br/>

    <h3>Coding Error in Server</h3>

      <a href="/oops">/oops</a> <br/>
      <a href="/json?invalid=1">/json?invalid=1</a> <br/>

    <h3>Cookies</h3>

      <pre>
      %s
      </pre>

  </body>
  <script>
    // TODO: create a <pre> to echo good response, a red <div> for error
    // And then do POST to /json-post
    $("input#json-post").click(function(event) {
      event.preventDefault();  // need to prevent the <a> behavior

      var message = $("textarea#user-json").val();
      //alert(message);

      $.ajax({
        type: "POST",
        url: "/json-post",
        contentType: "application/json",
        data: message,
        success: function(data) {
          // header is JSON, so it comes back parsed?
          $("pre#response").text(JSON.stringify(data));
        },
        error: function(jqXHR, textStatus, errorThrown) {
          var err = textStatus + ' ' + errorThrown + ' ' + jqXHR.responseText;
          $("div#ajax-status").text(err);
        }
      });
    });
  </script>
</html>
"""

class HomeHandler(object):

  def __call__(self, request):

    # Print out cookies
    lines = ['HomeHandler.  Received cookies:', '']
    for name, morsel in request.cookies.iteritems():
      lines.append('%s: %s (path=%s, expires=%s, domain=%s)' % (
          name, morsel.value, morsel['path'], morsel['expires'], morsel['domain']))
      lines.append('Morsel: ' + morsel.output(header=''))

    cookies = '\n'.join(cgi.escape(line) for line in lines)
    body = HOME % cookies
    return web.HtmlResponse(body)


class PlainTextHandler(object):

  def __call__(self, request):
    return web.PlainTextResponse('hello\nthere\n')


class HealthHandler(object):
  """
  Tests if the R process is up by sending it a request and having it echo it
  back.

  TODO: Add startup, we should send a request to all threads?  Block until they
  wake up.
  """

  def __init__(self, pool):
    self.pool = pool

    # TODO: Block until all processes have been initialized?

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

    req = ['1', '2']
    child.SendRequest(req)

    self.pool.Return(child)

    return web.PlainTextResponse('health')


class JsonHandler(object):

  def __call__(self, request):
    if request.query.get('invalid'):
      d = {'a': int}  # can't be serialized
    else:
      d = {'a': [1, 2.2, "three"], 'b': False}
    return web.JsonResponse(d)


class JsonPostHandler(object):

  def __call__(self, request):
    # Could the framework give a better error?  Echo content type?
    if not request.is_json_post:
      return web.ErrorResponse(
          web.BAD_REQUEST, "Expected JSON (check Content-Type)")

    # TODO: Use request.json 
    # You may need request.is_json?
    # Otherwise you can distinguish none from 'null'

    print 'Content Type', request.raw_environ['CONTENT_TYPE']

    return web.JsonResponse(request.json)


class RedirectHandler(object):

  def __call__(self, request):
    return web.RedirectResponse(
        web.TEMPORARY_REDIRECT, 'https://www.google.com')


class SetCookieHandler(object):
  
  def __call__(self, request):
    print request.query
    c = Cookie.SimpleCookie()

    c['foo'] = 'bar'
    # Spaces in key not allowed
    c['complex'] = 'three four ""' + " '' "

    return web.PlainTextResponse('SetCookieHandler\n', set_cookie=c)


class UserHandler(object):
  """Testing out extracting params from RegexRoute."""

  def __call__(self, request):
    body = 'User: %s' % request.path_groupdict['user']
    return web.PlainTextResponse(body)


class ListUsersHandler(object):
  """Uses relative URLs."""

  def __call__(self, request):
    body = """
    <a href="andy">andy</a> <br/>
    <a href="bob">bob</a> <br/>
    """
    return web.HtmlResponse(body)


class UrlEncodedPostHandler(object):
  """Test POST parsing."""

  def __call__(self, request):
    print request.form

    # TODO: Really should redirect to another page?
    body = 'name: %s' % request.form['name']
    print body
    return web.JsonResponse(request.form)


class MultiPartPostHandler(object):
  """Test POST parsing."""

  def __call__(self, request):
    print request.form
    data = { 'textname': request.form['textname'] }

    # TODO: each file has a mime type too?
    file1 = request.files.get('file1')
    file2 = request.files.get('file2')

    print 'FILES', request.files

    #print 'file1', file1
    #print 'file2', file2

    # Why are these false?  Need 'is not None' to test for existence then.
    print 'bool file1', bool(file1)
    print 'bool file2', bool(file2)

    if file1 is not None:
      data['file1_name'] = file1.filename
      data['file1_body'] = file1.file.read()
      data['file1_type'] = file1.type

    if file2 is not None:
      data['file2_name'] = file2.filename
      data['file2_body'] = file2.file.read()
      data['file2_type'] = file2.type

    return web.JsonResponse(data)


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
      ( web.ConstRoute('GET', '/text'),       PlainTextHandler()),
      ( web.ConstRoute('GET', '/json'),       JsonHandler()),
      ( web.ConstRoute('POST', '/json-post'), JsonPostHandler()),
      ( web.ConstRoute('GET', '/redirect'),   RedirectHandler()),
      ( web.ConstRoute('GET', '/set-cookie'), SetCookieHandler()),
      ( web.ConstRoute('POST', '/urlencoded-post'), UrlEncodedPostHandler()),
      ( web.ConstRoute('POST', '/multipart-post'), MultiPartPostHandler()),

      #( web.RegexRoute(
      #    'GET', '^ /static/ (?P<rel_path> \S*) $', flags=re.VERBOSE),
      #  webutil.StaticTreeHandler(static_dir)),

      # /users/ directory route?  Should redirect /users
      # Or maybe this is a layer on top
      #
      # webutil.ConstDirPairs('/users/', Handler)

      ( web.RegexRoute('GET', r'^ /users/ (?P<user>\w+) $', flags=re.VERBOSE),
        UserHandler()),
      ( web.ConstRoute('GET', '/oops'), OopsHandler()),
      ]

  #handlers.extend(webutil.DirectoryPairs('/users/', ListUsersHandler()))

  return web.App(handlers)


def main(argv):
  (opts, argv) = Options().parse_args(argv)

  app = CreateApp(opts)

  if opts.test_mode:
    print app
  else:
    wsgiref_server.ServeForever(app, port=opts.port)


if __name__ == '__main__':
  try:
    sys.exit(main(sys.argv))
  except RuntimeError, e:
    print >> sys.stderr, e.args[0]
    sys.exit(1)
