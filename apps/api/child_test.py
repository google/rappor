#!/usr/bin/python -S
"""
child_test.py: Tests for child.py
"""

import logging
import os
import sys
import unittest

import child  # module under test


logging.basicConfig(level=logging.INFO)  # So we see messages on stdout


class ChildTest(unittest.TestCase):

  def testSendHelloAndWait(self):
    tmp_dir = '_tmp/child_test'
    child.MakeDirs(tmp_dir)

    this_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    src = os.path.join(this_dir, '../..')

    c = child.Child(['../../handlers.R'], cwd=tmp_dir, env={'RAPPOR_SRC': src})

    c.Start()
    # Timeout: Do we need this?  I think we should just use a thread.
    c.SendHelloAndWait(10.0)
    c.SendHelloAndWait(10.0)

    # Health check
    c.SendRequest({'route': 'health', 'request': {"a": 1}})
    resp = c.RecvResponse()

    print repr(resp)


if __name__ == '__main__':
  unittest.main()
