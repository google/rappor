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

import cStringIO
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

  def testFromCsv(self):
    f = cStringIO.StringIO('k,h,m,p,q,f\n32,2,64,0.5,0.75,0.6\n')
    params = rappor.Params.from_csv(f)
    self.assertEqual(32, params.num_bloombits)
    self.assertEqual(64, params.num_cohorts)

    # Malformed header
    f = cStringIO.StringIO('k,h,m,p,q\n32,2,64,0.5,0.75,0.6\n')
    self.assertRaises(rappor.Error, rappor.Params.from_csv, f)

    # Missing second row
    f = cStringIO.StringIO('k,h,m,p,q,f\n')
    self.assertRaises(rappor.Error, rappor.Params.from_csv, f)

    # Too many rows
    f = cStringIO.StringIO('k,h,m,p,q,f\n32,2,64,0.5,0.75,0.6\nextra')
    self.assertRaises(rappor.Error, rappor.Params.from_csv, f)

  def testGetRapporMasksWithoutOnePRR(self):
    params = copy.copy(self.typical_instance)
    params.prob_f = 0.5  # For simplicity

    num_words = params.num_bloombits // 32 + 1
    rand = MockRandom()
    rand_funcs = rappor.SimpleRandFuncs(params, rand)
    rand_funcs.cohort_rand_fn = (lambda a, b: a)

    assigned_cohort, f_bits, mask_indices = rappor.get_rappor_masks(
        0, ["abc"], params, rand_funcs)

    self.assertEquals(0, assigned_cohort)
    self.assertEquals(0x000db6d, f_bits)  # dependent on 3 MockRandom values
    self.assertEquals(0x0006db6, mask_indices)

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
    rand_funcs = rappor.SimpleRandFuncs(params, rand)

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

    rand_funcs = rappor.SimpleRandFuncs(params, MockRandom())
    rand_funcs.cohort_rand_fn = lambda a, b: a
    e = rappor.Encoder(params, 0, rand_funcs=rand_funcs)

    cohort, bloom_bits_irr = e.encode("abc")

    self.assertEquals(0, cohort)
    self.assertEquals(0x000ffff, bloom_bits_irr)


class MockRandom(object):
  """Returns one of three random values in a cyclic manner.

  Mock random function that involves *some* state, as needed for tests that
  call randomness several times. This makes it difficult to deal exclusively
  with stubs for testing purposes.
  """

  def __init__(self):
    self.counter = 0
    # SimpleRandom will call self.random() below for each bit, which will
    # return these 3 values in sequence.
    self.randomness = [0.0, 0.6, 0.0]
    self.n = len(self.randomness)

  def seed(self, seed):
    self.counter = hash(seed) % self.n
    #print 'SEED', self.counter

  def getstate(self):
    #print 'GET STATE', self.counter
    return self.counter

  def setstate(self, state):
    #print 'SET STATE', state
    self.counter = state

  def randint(self, a, b):
    return a + self.counter

  def random(self):
    rand_val = self.randomness[self.counter]
    self.counter = (self.counter + 1) % self.n
    return rand_val


if __name__ == "__main__":
  unittest.main()
