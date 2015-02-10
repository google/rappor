# Copyright 2011 Google Inc.  All rights reserved.
# Use of this source code is governed by a BSD-style license that can be found
# in the COPYING file.

"""
file_io.py

Poly has to read from regular pipes, named pipes, and files.  This module does
that more safely than Python's I/O by using select() calls with timeouts.
"""

import array  # For efficient appending to buffers
import os
import select

import errors
#import env
import log

#tnet = env.Module('tnet')


class Error(Exception):
  pass

# 64 KB -- there might be a better magic number, but the named pipe size on my
# Ubuntu system was tested to be 64K.  This is used for both named pipes and
# disk files.  Disk buffer sizes may be different but it seems reasonable.
CHUNK_SIZE = 65536  
_NEWLINE = ord('\n')

def _GetLine(buf, pos):
  """Retrieve a line from a buffer, taking and updating a 'pos' index.

  Args:
    buf: array.array of bytes
    pos: Current position in the buffer

  Returns:
    line: A string line, or the empty string if none was found
    pos: New position in the buffer
  """
  n = len(buf)
  if not n:
    return '', pos
  i = pos
  eol_pos = -1
  while i < n:
    if buf[i] == _NEWLINE:
      eol_pos = i
      break
    i += 1
  if eol_pos != -1:
    s = pos
    e = eol_pos + 1
    pos = e
    return buf[s:e].tostring(), pos
  else:
    return '', pos  # same position


class PipeReader(object):
  """Read PGI responses from a pipe (regular or named pipe).

  - Uses 'select' to implement timeouts, protecting against slow applets
  - Uses 'array' to efficiently append to a buffer, rather than creating lots of
    new string objects
  """

  def __init__(self, fd, timeout=3.0, chunk_size=CHUNK_SIZE):
    """
    Args:
      fd: 
      timeout: timeout in seconds
    """
    self.fd = fd 
    self.timeout = timeout 
    self.chunk_size = chunk_size

    self.buf = array.array('B')  # array of bytes
    self.buf_pos = 0

  def _ReadChunk(self, chunk_size, timeout=None):
    """Read a chunk with a timeout.

    Returns:
      'chunk_size' bytes

    Raises:
      TimeoutError
    """
    #print '_ReadChunk', chunk_size
    assert chunk_size != 0, chunk_size
    timeout = timeout or self.timeout

    r, _, _ = select.select([self.fd], [], [], timeout)
    if len(r) == 0:
      raise errors.TimeoutError(
          'fd %d timed out after %f seconds' % (self.fd, timeout))
    elif len(r) == 1:
      bytes = os.read(r[0], chunk_size)
      #print 'read', len(bytes)
    else:
      raise AssertionError(r)
    return bytes

  def ReadLine(self):
    """Read a line with a timeout.

    Updates the internal buffer, since we aren't using readline() and can't read
    exactly 1 line.

    Returns:
      The line, or the empty string if we're at EOF.
    """
    while True:
      line, self.buf_pos = _GetLine(self.buf, self.buf_pos)
      if line:
        return line
      bytes = self._ReadChunk(self.chunk_size)
      # _ReadChunk uses select() to wait for the fd to ready. If we got no bytes
      # back then we assume the process has died (e.g. unhandled Python
      # exception), and we return an empty string to indicate EOF
      if not bytes:
        return ''
      self.buf.fromstring(bytes)

  def ReadUntil(self, delimiter, success_callback, error_callback):
    """Like the above, but first_line is read by the caller to check for a 404.
    """
    try:
      # Check for no content, return 404
      line = self.ReadLine()
      if line.strip() == delimiter:
        # Need to return the in this case!  There is some bad terminology,
        # because error_callback does not include errors.EmptyResponse, which
        # is an "expected" application "error" that results in a 404.
        success_callback()
        raise errors.EmptyResponse()
      yield line

      while True:
        line = self.ReadLine()
        if not line:
          break
        if line.strip() == delimiter:
          break
        yield line
    except errors.TimeoutError, e:  # TODO: expand this list of errors?
      log.info('ReadUntil got error %s, calling error callback and '
               're-raising', e)
      error_callback()
      raise
    else:
      success_callback()


class PipeReader2(object):
  """For PGI 2.

  - Uses 'select' to implement timeouts, protecting against slow applets
  - Uses 'array' to efficiently append to a buffer, rather than creating lots of
    new string objects
  """

  def __init__(self, fd, timeout=3.0):
    """
    Args:
      fd: File descriptor (not a file object)
      timeout: timeout in seconds
    """
    self.fd = fd
    self.timeout = timeout

    self.buf = array.array('B')  # array of bytes
    self.buf_pos = 0

  def _ReadChunk(self, chunk_size, timeout=None):
    """Read a chunk with a timeout.

    Returns:
      'chunk_size' bytes

    Raises:
      TimeoutError
    """
    #print '_ReadChunk', chunk_size
    assert chunk_size != 0, chunk_size
    timeout = timeout or self.timeout

    r, _, _ = select.select([self.fd], [], [], timeout)
    if len(r) == 0:
      raise errors.TimeoutError(
          'fd %d timed out after %f seconds' % (self.fd, timeout))
    elif len(r) == 1:
      bytes = os.read(r[0], chunk_size)
      #print 'read', len(bytes)
    else:
      raise AssertionError(r)
    return bytes

  def read(self, num_bytes):
    """Emulates file interface, but has a timeout.

    The timeout is sort of broken since it applies to each call of _ReadChunk.
    This is a place holder until we switch to an event loop, which allow proper
    timeouts.
    """
    buf = ''
    bytes_left = num_bytes
    while bytes_left > 0:
      bytes = self._ReadChunk(bytes_left)
      if not bytes:  # See above, pipe is broken
        break
      buf += bytes
      bytes_left -= len(bytes)
    return buf


def DiskFileContents(f,
                     success_callback=lambda: None,
                     error_callback=lambda: None):
  """Yield the contents of a disk file."""
  try:
    while True:
      chunk = f.read(CHUNK_SIZE)
      if not chunk:
        break
      yield chunk
    f.close()  # Make sure to close it since we're a long-running server!
  except KeyboardInterrupt:
    raise
  except Exception, e:
    error_callback()
  else:
    success_callback()
