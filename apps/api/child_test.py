#!/usr/bin/python -S
"""
child_test.py: Tests for child.py
"""

import unittest

import child  # module under test


class ChildTest(unittest.TestCase):

  def testSendHelloAndWait(self):
    child.MakeDir('_test')

    c = child.Child(
        ['../pages.R'], input='fifo', output='fifo',
        cwd='_test',
        pgi_version=2,
        pgi_format='json',
        )
    c.Start()
    # Timeout: Do we need this?  I think we should just use a thread.
    c.SendHelloAndWait(10.0)

    c.SendHelloAndWait(10.0)

    c.SendRequest({'foo': 'bar'})
    f = c.OutputStream()
    resp = f.readline()

    print repr(resp)


if __name__ == '__main__':
  unittest.main()
