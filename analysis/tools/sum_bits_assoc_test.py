#!/usr/bin/python -S
#
# Copyright 2015 Google Inc. All rights reserved.
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
sum_bits_assoc_test.py: Tests for sum_bits_assoc.py
"""

import cStringIO
import unittest

import rappor
import sum_bits_assoc  # module under test


# The header doesn't matter
CSV_IN = """\
user_id,cohort,irr1,irr2  
5,1,0011,1010
5,1,0011,1010
5,1,0000,0000
"""

# ###############################
# EXPECTED_F_2WAY
#
# NOTE: bit order is reversed.
# First row is 65 zeroes because there are no reports with cohort 0
expected_f_2way = """\
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,\
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0\r
"""

# Cohort 1
# Total # of reports
expected_f_2way = expected_f_2way + "3,"

# Looking at LSBs of both irrs
# Total # of (11, 01, 10, 00) that appear
expected_f_2way = expected_f_2way + "0,0,2,1,"

# Report 1-major order. So looking at LSB of irr1 and 2nd LSB of irr2
expected_f_2way = expected_f_2way + "2,0,0,1,"

# And so on ...
expected_f_2way = expected_f_2way + "0,0,2,1,"
expected_f_2way = expected_f_2way + "2,0,0,1,"

# Now moving on to 2nd LSB of irr1
expected_f_2way = expected_f_2way + ("0,0,2,1,2,0,0,1," * 2)

# Now moving on to 3rd LSB of irr1
# Note that for 3rd LSB of irr1 and LSB of irr2, there are three 00s
expected_f_2way = expected_f_2way + ("0,0,0,3,0,2,0,1," * 2)
# MSB of irr1
expected_f_2way = expected_f_2way + "0,0,0,3,0,2,0,1," + "0,0,0,3,0,2,0,1\r\n"

# EXPECTED_F_2WAY is a constant
EXPECTED_F_2WAY = expected_f_2way

# end of EXPECTED_F_2WAY
# ###############################

# NOTE: bit order is reversed.
EXPECTED_F_1 = """\
0,0,0,0,0\r
3,2,2,0,0\r
"""

# NOTE: bit order is reversed.
EXPECTED_F_2 = """\
0,0,0,0,0\r
3,0,2,0,2\r
"""

WRONG_IRR_BITS = """\
user_id,cohort,irr1,irr2
cli1,1,00123,11223
"""

WRONG_COHORT = """\
user_id,cohort,irr1,irr2
cli1,3,0011,0001
"""

class SumBitsAssocTest(unittest.TestCase):

  def setUp(self):
    self.params = rappor.Params()
    self.params.num_bloombits = 4
    self.params.num_cohorts = 2
    self.maxDiff = None

  def testSum(self):
    stdin = cStringIO.StringIO(CSV_IN)
    f_2way = cStringIO.StringIO()
    f_1 = cStringIO.StringIO()
    f_2 = cStringIO.StringIO()

    sum_bits_assoc.SumBits(self.params, self.params, stdin, f_2way, f_1, f_2)
    self.assertMultiLineEqual(EXPECTED_F_1, f_1.getvalue())
    self.assertMultiLineEqual(EXPECTED_F_2, f_2.getvalue())
    self.assertMultiLineEqual(EXPECTED_F_2WAY, f_2way.getvalue())

  def testErrors(self):
    f_2way = cStringIO.StringIO()
    f_1 = cStringIO.StringIO()
    f_2 = cStringIO.StringIO()

    stdin = cStringIO.StringIO(WRONG_IRR_BITS)
    self.assertRaises(
        RuntimeError, sum_bits_assoc.SumBits, self.params, self.params, stdin,
        f_2way, f_1, f_2)

    stdin = cStringIO.StringIO(WRONG_COHORT)
    self.assertRaises(
        RuntimeError, sum_bits_assoc.SumBits, self.params, self.params, stdin,
        f_2way, f_1, f_2)


if __name__ == '__main__':
  unittest.main()
