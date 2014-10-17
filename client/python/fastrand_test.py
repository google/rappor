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
fastrand_test.py: Tests for _fastrand extension module.
"""

import unittest

import _fastrand  # module under test


class FastRandTest(unittest.TestCase):

  def testRandbits64(self):
    for n in [8, 16, 32, 64]:
      #print '== %d' % n
      for p1 in [0.1, 0.5, 0.9]:
        #print '-- %f' % p1
        for i in xrange(5):
          r = _fastrand.randbits(p1, n)
          # Rough sanity check
          self.assertLess(r, 2 ** n)

          # Visual check
          #b = bin(r)
          #print b
          #print b.count('1')

  def testRandbitsError(self):
    r = _fastrand.randbits(-1, 64)
    # TODO: Should probably raise exceptions
    self.assertEqual(None, r)

    r = _fastrand.randbits(0.0, 65)
    self.assertEqual(None, r)


if __name__ == '__main__':
  unittest.main()
