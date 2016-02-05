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

# NOTE: We could retire this module in favor of the C++ client?  One reason to
# keep it is if it supports a wider range of params (e.g. more than 32 or 64
# bits.)

import random

import _fastrand


class FastIrrRand(object):
  """Fast insecure version of rappor.SecureIrrRand."""

  def __init__(self, params):
    randbits = _fastrand.randbits  # accelerated function
    num_bits = params.num_bloombits

    # IRR probabilities
    self.p_gen = lambda: randbits(params.prob_p, num_bits)
    self.q_gen = lambda: randbits(params.prob_q, num_bits)
