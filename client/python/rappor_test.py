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
rappor_test.py: Tests for rappor.py

NOTE! This contains tests that might fail with very small
probability (< 1 in 10,000 times). This is implicitly required
for testing probability. Such tests start with the stirng "testProbFailure."
"""

import copy
import math
import random
import unittest

import rappor  # module under test


class RapporParamsTest(unittest.TestCase):

  def setUp(self):
    self.typical_instance = rappor.Params()
    ti = self.typical_instance  # For convenience
    ti.num_cohorts = 64        # Number of cohorts
    ti.num_hashes = 2          # Number of bloom filter hashes
    ti.num_bloombits = 16      # Number of bloom filter bits
    ti.prob_p = 0.40           # Probability p
    ti.prob_q = 0.70           # Probability q
    ti.prob_f = 0.30           # Probability f

    # TODO: Move this to constructor, or add a different constructor
    ti.flag_oneprr = False     # One PRR for each user/word pair

  def tearDown(self):
    pass

  def testApproxRandom(self):
    get_rand_bits = rappor.ApproxRandom(0.1, 2)
    r = get_rand_bits()
    print r, bin(r)

  def testSimpleRandom(self):
    # TODO: measure speed of naive implementation
    return
    for i in xrange(100000):
      r = rappor.get_rand_bits2(0.1, 2, lambda: random.getrandbits(32))
      if i % 10000 == 0:
        print i
      #print r, [bin(a) for a in r]

  def testProbFailureWeakStatisticalTestForGetRandBits(self):
    """Tests whether get_rand_bits outputs correctly biased random bits.

    NOTE! This is a test with a small failure probability.
    The test succeeds with very very high probability and should only fail
    1 in 10,000 times or less.

    Samples 256 bits of randomness 1000 times and checks to see that the
    cumulative number of bits set in each of the 256 positions is within
    3 \sigma of the mean

    Repeats this experiment with several probability values
    """
    return
    length_in_words = 8  # A good sample size to test; 256 bits
    rand_fn = (lambda: random.getrandbits(32))
    # NOTE: 0.0 and 1.0 are not handled exactly.
    p_values = [0.5, 0.36, 0.9]

    # Trials with different probabilities from p[]
    for p in p_values:
      get_rand_bits = rappor.ApproxRandom(p, length_in_words)

      set_bit_count = [0] * 256
      for _ in xrange(1000):
        rand_sample = get_rand_bits()

        bin_str = bin(rand_sample)[2:]   # i^th word in binary as a str
                                            # +2 for the 0b prefix
        #print bin_str

        # Prefix with leading zeroes
        bin_str = "0" * (32 - len(bin_str)) + bin_str
        for j in xrange(32):
          if bin_str[j] == "1":
            set_bit_count[32 + j] += 1

      mean = int(1000 * p)
      # variance of N samples = Np(1-p)
      stddev = math.sqrt(1000 * p * (1 - p))
      num_infractions = 0  # Number of values over 3 \sigma
      infractions = []
      for i in xrange(length_in_words):
        for j in xrange(32):
          s = set_bit_count[i * 32 + j]
          if s > (mean + 3 * stddev) or s < (mean - 3 * stddev):
            num_infractions += 1
            infractions.append(s)

      # 99% confidence for 3 \sigma implies less than 10 errors in 1000
      # Factor 2 to avoid flakiness as there is a 1% sampling rate error
      self.assertTrue(
          num_infractions <= 20, '%s %s' % (num_infractions, infractions))

  def testUpdateRapporSumsWithLessThan32BitBloomFilter(self):
    report = 0x1d  # From LSB, bits 1, 3, 4, 5 are set
    # Empty rappor_sum
    rappor_sum = [[0] * (self.typical_instance.num_bloombits + 1)
                  for _ in xrange(self.typical_instance.num_cohorts)]
    # A random cohort number
    cohort = 42

    # Setting up expected rappor sum
    expected_rappor_sum = [[0] * (self.typical_instance.num_bloombits + 1)
                           for _ in xrange(self.typical_instance.num_cohorts)]
    expected_rappor_sum[42][0] = 1
    expected_rappor_sum[42][1] = 1
    expected_rappor_sum[42][3] = 1
    expected_rappor_sum[42][4] = 1
    expected_rappor_sum[42][5] = 1

    rappor.update_rappor_sums(rappor_sum, report, cohort,
                              self.typical_instance)
    self.assertEquals(expected_rappor_sum, rappor_sum)

  def testGetRapporMasksWithoutOnePRR(self):
    params = copy.copy(self.typical_instance)
    params.prob_f = 0.5  # For simplicity

    num_words = params.num_bloombits // 32 + 1
    rand = MockRandom()
    uniform_gen = rappor.ApproxRandom(0.5, num_words, rand=rand)
    f_gen = rappor.ApproxRandom(params.prob_f, num_words, rand=rand)
    rand_funcs = rappor.ApproxRandFuncs(params, rand)
    rand_funcs.cohort_rand_fn = (lambda a, b: a)

    assigned_cohort, f_bits, mask_indices = rappor.get_rappor_masks(
        0, ["abc"], params, rand_funcs)

    self.assertEquals(0, assigned_cohort)
    self.assertEquals(0xfff0000f, f_bits)
    self.assertEquals(0x0ffff000, mask_indices)

  def testGetBFBit(self):
    cohort = 0
    hash_no = 0
    input_word = "abc"
    ti = self.typical_instance
    # expected_hash = ("\x13O\x0b\xa0\xcc\xc5\x89\x01oI\x85\xc8\xc3P\xfe\xa7 H"
    #                  "\xb0m")
    # Output should be
    # (ord(expected_hash[0]) + ord(expected_hash[1])*256) % 16
    expected_output = 3
    actual = rappor.get_bf_bit(input_word, cohort, hash_no, ti.num_bloombits)
    self.assertEquals(expected_output, actual)

    hash_no = 1
    # expected_hash = ("\xb6\xcc\x7f\xee@\x95\xb0\xdb\xf5\xf1z\xc7\xdaPM"
    #                  "\xd4\xd6u\xed3")
    expected_output = 6
    actual = rappor.get_bf_bit(input_word, cohort, hash_no, ti.num_bloombits)
    self.assertEquals(expected_output, actual)

  def testGetRapporMasksWithOnePRR(self):
    # Set randomness function to be used to sample 32 random bits
    # Set randomness function that takes two integers and returns a
    # random integer cohort in [a, b]

    params = copy.copy(self.typical_instance)
    params.flag_oneprr = True

    num_words = params.num_bloombits // 32 + 1
    rand = MockRandom()
    rand_funcs = rappor.ApproxRandFuncs(params, rand)

    # First two calls to get_rappor_masks for identical inputs
    # Third call for a different input
    print '\tget_rappor_masks 1'
    cohort_1, f_bits_1, mask_indices_1 = rappor.get_rappor_masks(
        "0", "abc", params, rand_funcs)
    print '\tget_rappor_masks 2'
    cohort_2, f_bits_2, mask_indices_2 = rappor.get_rappor_masks(
        "0", "abc", params, rand_funcs)
    print '\tget_rappor_masks 3'
    cohort_3, f_bits_3, mask_indices_3 = rappor.get_rappor_masks(
        "0", "abcd", params, rand_funcs)

    # First two outputs should be identical, i.e., identical PRRs
    self.assertEquals(f_bits_1, f_bits_2)
    self.assertEquals(mask_indices_1, mask_indices_2)
    self.assertEquals(cohort_1, cohort_2)

    # Third PRR should be different from the first PRR
    self.assertNotEqual(f_bits_1, f_bits_3)
    self.assertNotEqual(mask_indices_1, mask_indices_3)
    self.assertNotEqual(cohort_1, cohort_3)

    # Now testing with flag_oneprr false
    params.flag_oneprr = False
    cohort_1, f_bits_1, mask_indices_1 = rappor.get_rappor_masks(
        "0", "abc", params, rand_funcs)
    cohort_2, f_bits_2, mask_indices_2 = rappor.get_rappor_masks(
        "0", "abc", params, rand_funcs)

    self.assertNotEqual(f_bits_1, f_bits_2)
    self.assertNotEqual(mask_indices_1, mask_indices_2)
    self.assertNotEqual(cohort_1, cohort_2)

  def testEncoder(self):
    """Expected bloom bits is computed as follows.

    f_bits = 0xfff0000f and mask_indices = 0x0ffff000 from
    testGetRapporMasksWithoutPRR()

    q_bits = 0xfffff0ff from mock_rand.randomness[] and how get_rand_bits works
    p_bits = 0x000ffff0 from -- do --

    bloom_bits_array is 0x0000 0048 (3rd bit and 6th bit, from
    testSetBloomArray, are set)

    Bit arithmetic ends up computing
    bloom_bits_prr = 0x0ff00048
    bloom_bits_irr= = 0x0ffffff8
    """
    params = copy.copy(self.typical_instance)
    params.prob_f = 0.5
    params.prob_p = 0.5
    params.prob_q = 0.75

    rand_funcs = rappor.ApproxRandFuncs(params, MockRandom())
    rand_funcs.cohort_rand_fn = lambda a, b: a
    e = rappor.Encoder(params, 0, rand_funcs=rand_funcs)

    cohort, bloom_bits_irr = e.encode("abc")

    self.assertEquals(0, cohort)
    self.assertEquals(0x0ffffff8, bloom_bits_irr)


class MockRandom(object):
  """Returns one of eight random strings in a cyclic manner.

  Mock random function that involves *some* state, as needed for tests
  that call randomness several times. This makes it difficult to deal
  exclusively with stubs for testing purposes.
  """

  def __init__(self):
    self.counter = 0
    self.randomness = [0x0000ffff, 0x000ffff0, 0x00ffff00, 0x0ffff000,
                       0xfff000f0, 0xfff0000f, 0xf0f0f0f0, 0xff0f00ff]

  def seed(self, seed):
    self.counter = hash(seed) % 8
    #print 'SEED', self.counter

  def getstate(self):
    #print 'GET STATE', self.counter
    return self.counter

  def setstate(self, state):
    #print 'SET STATE', state
    self.counter = state

  def getrandbits(self, unused_num_bits):
    #print 'GETRAND', self.counter
    rand_val = self.randomness[self.counter]
    self.counter = (self.counter + 1) % 8
    return rand_val

  def randint(self, a, b):
    return a + self.counter


if __name__ == "__main__":
  unittest.main()
