// Copyright 2015 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "libc_rand_impl.h"

#include <assert.h>
#include <stdint.h>  // uint64_t
//#include <stdio.h>  // printf
#include <stdlib.h>  // srand
#include <time.h>  // time

static bool gInitialized = false;

namespace rappor {

void LibcRandGlobalInit() {
  int seed = time(NULL);
  srand(seed);  // seed with nanoseconds
  gInitialized = true;
}

//
// LibcRand
//

// Similar to client/python/fastrand.c
Bits LibcRand::CreateMask(int rand_threshold) const {
  Bits result = 0;
  for (int i = 0; i < num_bits_; ++i) {
    Bits bit = (rand() < rand_threshold);
    result |= (bit << i);
  }
  return result;
}

LibcRand::LibcRand(int num_bits, float p, float q)
    : IrrRandInterface(num_bits, p, q) {
  p_rand_threshold_ = static_cast<int>(p * RAND_MAX);
  q_rand_threshold_ = static_cast<int>(q * RAND_MAX);
}

bool LibcRand::PMask(Bits* mask_out) const {
  *mask_out = CreateMask(p_rand_threshold_);
  return true;
}

bool LibcRand::QMask(Bits* mask_out) const {
  *mask_out = CreateMask(q_rand_threshold_);
  return true;
}

}  // namespace rappor
