#!/usr/bin/python -S
"""
combine_results_test.py: Tests for combine_results.py
"""

import csv
import cStringIO
import unittest

import combine_results  # module under test


# TODO: Make these test more the header row.  They rely heavily on the file
# system!

class CombineResultsTest(unittest.TestCase):

  def testCombineDistResults(self):
    stdin = cStringIO.StringIO('')
    out = cStringIO.StringIO()
    c_out = csv.writer(out)

    combine_results.CombineDistResults(stdin, c_out, 10)
    actual = out.getvalue()
    self.assert_(actual.startswith('date'), actual)

  def testCombineAssocResults(self):
    stdin = cStringIO.StringIO('')
    out = cStringIO.StringIO()
    c_out = csv.writer(out)

    combine_results.CombineAssocResults(stdin, c_out, 10)
    actual = out.getvalue()
    self.assert_(actual.startswith('dummy'), actual)


if __name__ == '__main__':
  unittest.main()
