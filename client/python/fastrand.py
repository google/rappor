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

"""fastrand.py - Python wrapper for _fastrand."""

import random

import _fastrand


class FastRandFuncs(object):

  def __init__(self, params):
    # NOTE: no rand attribute, so no seeding or getstate/setstate.
    # Also duplicating some of rappor._RandFuncs.
    self.cohort_rand_fn = random.randint

    randbits = _fastrand.randbits
    num_bits = params.num_bloombits
    self.f_gen = lambda: randbits(params.prob_f, num_bits)
    self.p_gen = lambda: randbits(params.prob_p, num_bits)
    self.q_gen = lambda: randbits(params.prob_q, num_bits)
    self.uniform_gen = lambda: randbits(0.5, num_bits)
