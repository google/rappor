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

"""RAPPOR client library.

Privacy is ensured without a third party by only sending RAPPOR'd data over the
network (as opposed to raw client data).

Note that we use SHA1 for the Bloom filter hash function.
"""
import hashlib
import random


class Params(object):
  """RAPPOR encoding parameters.

  These affect privacy/anonymity.  See the paper for details.
  """
  def __init__(self):
    self.num_bloombits = 16      # Number of bloom filter bits (k)
    self.num_hashes = 2          # Number of bloom filter hashes (h)
    self.num_cohorts = 64        # Number of cohorts (m)
    self.prob_p = 0.50           # Probability p
    self.prob_q = 0.75           # Probability q
    self.prob_f = 0.50           # Probability f

    self.flag_oneprr = False     # One PRR for each user/word pair

  # For testing
  def __eq__(self, other):
    return self.__dict__ == other.__dict__

  def __repr__(self):
    return repr(self.__dict__)


class SimpleRandom(object):
  """Returns N 32-bit words where each bit has probability p of being 1."""

  def __init__(self, prob_one, num_bits, rand=None):
    self.prob_one = prob_one
    self.num_bits = num_bits
    self.rand = rand or random.Random()

  def __call__(self):
    p = self.prob_one
    rand_fn = self.rand.random  # cache it for speed

    r = 0
    for i in xrange(self.num_bits):
      bit = rand_fn() < p
      r |= (bit << i)  # using bool as int
    return r


# NOTE: This doesn't seem faster.

class ApproxRandom(object):
  """Like SimpleRandom, but tries to make fewer random calls.

  Represent prob_one in base 2 repr (up to 6 bits = 2^-6 accuracy)
  If X is a random bit with             Pr[b=1] = p
    X & uniform is a random bit with    Pr[b=1] = p/2
    X | uniform is a random bit with    Pr[b=1] = p/2+1/2
  Read prob_one from LSB and do & or | operations depending on
  whether the bit is set or not a la repeated-squaring.
  #
  Eg. 0.3 = (0.010011...)_2 ~
        unif & (unif | (unif & (unif & (unif | unif))))
             0       1       0       0       1  1

  Takes as input Pr[b=1], length of random bits, and a randomness
  function that outputs 32 bits. When not debugging, set rand_fn
  to random.getrandbits(32)
  """

  def __init__(self, prob_one, num_bits, rand=None):
    """
    Args:
      rand: object satisfying Python random.Random() interface.
    """
    if not isinstance(prob_one, float):
      raise RuntimeError('Probability must be a float')

    if not (0 <= prob_one <= 1):
      raise RuntimeError('Probability not in [0,1]: %s' % prob_one)

    self.num_bits = num_bits
    self.rand = rand or random.Random()

    # This calculation depends on prob_one, but not the actual randomness.
    self.bits_in_prob_one = [0] * 6  # Store prob_one in bits
    for i in xrange(0, 6):  # Loop at most six times
      if prob_one < 0.5:
        self.bits_in_prob_one[i] = 0
        prob_one *= 2
      else:
        self.bits_in_prob_one[i] = 1
        prob_one = prob_one * 2 - 1

      if prob_one <= 0.01:  # Finish loop early if less than 1% already
        break

  def __call__(self):
    num_bits = self.num_bits
    rand_fn = lambda: self.rand.getrandbits(self.num_bits)

    # We could special case these to be exact, but we're not using them for f,
    # p, q.  Better to use the non-approximate method.

    #if self.prob_one == 0:
    #  return [0] * self.num_bits
    #if self.prob_one == 1:
    #  return [0xffffffff] * self.num_bits

    rand_bits = 0
    and_or = self.bits_in_prob_one

    for i in xrange(5, -1, -1):  # Count down from 5 to 0
      if and_or[i] == 0:  # Corresponds to X & uniform
        rand_bits &= rand_fn()
      else:
        rand_bits |= rand_fn()

    return rand_bits


class _RandFuncs(object):
  """Base class for randomness."""

  def __init__(self, params, rand):
    """
    Args:
      params: RAPPOR parameters
      rand: object satisfying random.Random() interface.
    """
    self.rand = rand
    self.num_bits = params.num_bloombits
    self.cohort_rand_fn = rand.randint


class SimpleRandFuncs(_RandFuncs):

  def __init__(self, params, rand):
    _RandFuncs.__init__(self, params, rand)

    self.f_gen = SimpleRandom(params.prob_f, self.num_bits, rand)
    self.p_gen = SimpleRandom(params.prob_p, self.num_bits, rand)
    self.q_gen = SimpleRandom(params.prob_q, self.num_bits, rand)
    self.uniform_gen = SimpleRandom(0.5, self.num_bits, rand)


class ApproxRandFuncs(_RandFuncs):

  def __init__(self, params, rand):
    _RandFuncs.__init__(self, params, rand)

    self.f_gen = ApproxRandom(params.prob_f, self.num_bits, rand)
    self.p_gen = ApproxRandom(params.prob_p, self.num_bits, rand)
    self.q_gen = ApproxRandom(params.prob_q, self.num_bits, rand)
    # uniform generator (NOTE: could special case this)
    self.uniform_gen = ApproxRandom(0.5, self.num_bits, rand)


# Compute masks for rappor's Permanent Randomized Response
# The i^th Bloom Filter bit B_i is set to be B'_i equals
# 1  w/ prob f/2 -- (*) -- f_bits
# 0  w/ prob f/2
# B_i w/ prob 1-f -- (&) -- mask_indices set to 0 here, i.e., no mask
# Output bit indices corresponding to (&) and bits 0/1 corresponding to (*)
def get_rappor_masks(user_id, word, params, rand_funcs):
  """
  Call 3 random functions.  Seed deterministically beforehand if oneprr.
  TODO:
  - Rewrite this to be clearer.  We can use a completely different Random()
    instance in the case of oneprr.
  - Expose it in the simulation.  It doesn't appear to be exercised now.
  """
  if params.flag_oneprr:
    stored_state = rand_funcs.rand.getstate()  # Store state
    rand_funcs.rand.seed(user_id + word)  # Consistently seeded

  assigned_cohort = rand_funcs.cohort_rand_fn(0, params.num_cohorts - 1)
  # Uniform bits for (*)
  f_bits = rand_funcs.uniform_gen()
  # Mask indices are 1 with probability f.
  mask_indices = rand_funcs.f_gen()

  if params.flag_oneprr:                    # Restore state
    rand_funcs.rand.setstate(stored_state)

  return assigned_cohort, f_bits, mask_indices


def get_bf_bit(input_word, cohort, hash_no, num_bloombits):
  """Returns the bit to set in the Bloom filter."""
  h = '%s%s%s' % (cohort, hash_no, input_word)
  sha1 = hashlib.sha1(h).digest()
  # Use last two bytes as the hash.  We to allow want more than 2^8 = 256 bits,
  # but 2^16 = 65536 is more than enough.  Default is 16 bits.
  a, b = sha1[0], sha1[1]
  return (ord(a) + ord(b) * 256) % num_bloombits


class Encoder(object):
  """Obfuscates values for a given user using the RAPPOR privacy algorithm."""

  def __init__(self, params, user_id, rand_funcs=None):
    """
    Args:
      params: RAPPOR Params() controlling privacy
      user_id: user ID, for generating cohort.  (In the simulator, each user
        gets its own Encoder instance.)
      rand_funcs: randomness, can be deterministic for testing.
    """
    self.params = params  # RAPPOR params
    self.user_id = user_id

    self.rand_funcs = rand_funcs
    self.p_gen = rand_funcs.p_gen
    self.q_gen = rand_funcs.q_gen

  def encode(self, word):
    """Compute rappor (Instantaneous Randomized Response)."""
    params = self.params

    cohort, f_bits, mask_indices = get_rappor_masks(self.user_id, word,
                                                    params,
                                                    self.rand_funcs)

    bloom_bits_array = 0
    # Compute Bloom Filter
    for hash_no in xrange(params.num_hashes):
      bit_to_set = get_bf_bit(word, cohort, hash_no, params.num_bloombits)
      bloom_bits_array |= (1 << bit_to_set)

    # Both bit manipulations below use the following fact:
    # To set c = a if m = 0 or b if m = 1
    # c = (a & not m) | (b & m)
    #
    # Compute PRR as
    # f_bits if mask_indices = 1
    # bloom_bits_array if mask_indices = 0

    # TODO: change 0xffff ^ to ~
    prr = (f_bits & mask_indices) | (bloom_bits_array & ~mask_indices)
    #print 'prr', bin(prr)

    # Compute instantaneous randomized response:
    # If PRR bit is set, output 1 with probability q
    # If PRR bit is not set, output 1 with probability p
    p_bits = self.p_gen()
    q_bits = self.q_gen()

    #print bin(f_bits), bin(mask_indices), bin(p_bits), bin(q_bits)

    irr = (p_bits & ~prr) | (q_bits & prr)
    #print 'irr', bin(irr)

    return cohort, irr  # irr is the rappor


# Update rappor sum
def update_rappor_sums(rappor_sum, rappor, cohort, params):
  for bit_num in xrange(params.num_bloombits):
    if rappor & (1 << bit_num):
      rappor_sum[cohort][1 + bit_num] += 1
  rappor_sum[cohort][0] += 1  # The 0^th entry contains total reports in cohort
