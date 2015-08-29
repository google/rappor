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

// IMPORTANT: This is for demo /simulation purposes only.  Use a better random
// function in production applications.

#include "libc_rand_impl.h"

#include <assert.h>
#include <stdint.h>  // uint64_t
#include <stdlib.h>  // srand

namespace rappor {

//
// LibcRand
//

// Similar to client/python/fastrand.c
bool LibcRand::GetMask(float prob, int num_bits, Bits* mask_out) const {
  int rand_threshold = static_cast<int>(prob * RAND_MAX);
  Bits mask = 0;

  for (int i = 0; i < num_bits; ++i) {
    // NOTE: could use rand_r(), which is more thread-safe
    Bits bit = (rand() < rand_threshold);
    mask |= (bit << i);
  }
  *mask_out = mask;
  return true;  // no possible failure
}

}  // namespace rappor
