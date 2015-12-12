#!/usr/bin/python -S
"""
combine_status_test.py: Tests for combine_status.py
"""

import csv
import cStringIO
import unittest

import combine_status  # module under test


# TODO: Make these test more the header row.  They rely heavily on the file
# system!

class CombineStatusTest(unittest.TestCase):

  def testCombineDistTaskStatus(self):
    stdin = cStringIO.StringIO('')
    out = cStringIO.StringIO()
    c_out = csv.writer(out)

    combine_status.CombineDistTaskStatus(stdin, c_out, {})
    actual = out.getvalue()
    self.assert_(actual.startswith('job_id,params_file,'), actual)

  def testCombineAssocTaskStatus(self):
    stdin = cStringIO.StringIO('')
    out = cStringIO.StringIO()
    c_out = csv.writer(out)

    combine_status.CombineAssocTaskStatus(stdin, c_out)
    actual = out.getvalue()
    self.assert_(actual.startswith('job_id,metric,'), actual)


if __name__ == '__main__':
  unittest.main()
