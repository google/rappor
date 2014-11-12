#!/usr/bin/python -S
"""
sum_bits_test.py: Tests for sum_bits.py
"""

import cStringIO
import unittest

import rappor
import sum_bits  # module under test


CSV_IN = """\
user_id,cohort,rappor
5,1,0000111100001111
5,1,0000000000111100
"""

# NOTE: bit order is reversed.
EXPECTED_CSV_OUT = """\
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0\r
2,1,1,2,2,1,1,0,0,1,1,1,1,0,0,0,0\r
"""

TOO_MANY_COLUMNS = """\
user_id,cohort,rappor
5,1,0000111100001111,extra
"""


class SumBitsTest(unittest.TestCase):

  def setUp(self):
    self.params = rappor.Params()
    self.params.num_bloombits = 16
    self.params.num_cohorts = 2

  def testSum(self):
    stdin = cStringIO.StringIO(CSV_IN)
    stdout = cStringIO.StringIO()

    sum_bits.SumBits(self.params, stdin, stdout)

    self.assertMultiLineEqual(EXPECTED_CSV_OUT, stdout.getvalue())

  def testErrors(self):
    stdin = cStringIO.StringIO(TOO_MANY_COLUMNS)
    stdout = cStringIO.StringIO()

    self.assertRaises(
        RuntimeError, sum_bits.SumBits, self.params, stdin, stdout)


if __name__ == '__main__':
  unittest.main()
