#!/usr/bin/python
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
rappor_params_test.py: Tests for rappor_params.py
"""

import unittest

import rappor_sim  # module under test


class RapporParamsTest(unittest.TestCase):
  def setUp(self):
    pass

  def tearDown(self):
    pass

  def testParseArgs(self):
    expected = rappor_sim.RapporInstance()
    p = expected.params
    p.num_bloombits = 16      # Number of bloom filter bits
    p.num_hashes = 2          # Number of bloom filter hashes
    p.num_cohorts = 64        # Number of cohorts
    p.prob_p = 0.40           # Probability p
    p.prob_q = 0.70           # Probability q
    p.prob_f = 0.30           # Probability f
    p.flag_oneprr = False     # One PRR for each user/word pair

    expected.infile = "test.txt"             # Input file name
    expected.outfile = "test_out.csv"        # Output file name
    expected.histfile = "test_hist.csv"      # Output histogram file
    expected.mapfile = "test_map.csv"        # Output BF map file
    expected.paramsfile = "test_params.csv"  # Output params file

    arg_string = ("script --cohorts 64 --hashes 2 --bloombits 16 -p 0.4"
                  " -q 0.7 -f 0.3 -i test.txt")
    arg = arg_string.strip().split()
    result, error = rappor_sim.parse_args(arg)

    self.assertEquals(expected, result)
    self.assertEquals(error, rappor_sim.PARSE_SUCCESS)


if __name__ == "__main__":
  unittest.main()
