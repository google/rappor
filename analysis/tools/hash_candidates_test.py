#!/usr/bin/python -S
#
# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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
apple,5,1,26,26,38,34,63,62\r
banana,12,14,28,24,37,34,62,49\r
carrot,4,12,25,21,48,38,61,54\r
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
