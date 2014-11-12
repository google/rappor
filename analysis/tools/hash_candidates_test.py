#!/usr/bin/python -S
"""
hash_candidates_test.py: Tests for hash_candidates.py
"""

import cStringIO
import unittest

import rappor
import hash_candidates  # module under test


STDIN = """\
apple
banana
carrot
"""

EXPECTED_CSV_OUT = """\
apple,2,16,19,32,37,47,52,55\r
banana,4,16,26,23,45,34,56,62\r
carrot,16,8,24,30,42,33,64,62\r
"""


class HashCandidatesTest(unittest.TestCase):

  def setUp(self):
    self.params = rappor.Params()
    self.params.num_bloombits = 16
    self.params.num_cohorts = 4
    self.params.num_hashes = 2

  def testHash(self):
    stdin = cStringIO.StringIO(STDIN)
    stdout = cStringIO.StringIO()

    hash_candidates.HashCandidates(self.params, stdin, stdout)

    self.assertMultiLineEqual(EXPECTED_CSV_OUT, stdout.getvalue())


if __name__ == '__main__':
  unittest.main()
