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

#include "unix_kernel_rand_impl.h"

#include <stdint.h>  // uint64_t

//#include "rappor.h"  // log

namespace rappor {

const int kMaxBitWidth = 32;

bool UnixKernelRand::CreateMask(uint8_t threshold256, Bits* mask_out) const {
  uint8_t rand_buf[kMaxBitWidth];
  size_t num_elems = fread(&rand_buf, sizeof(uint8_t), num_bits_, fp_);
  if (num_elems != static_cast<size_t>(num_bits_)) {  // error on fread error
    return false;
  }

  Bits mask = 0;
  for (int i = 0; i < num_bits_; ++i) {
    uint8_t bit = (rand_buf[i] < threshold256);
    mask |= (bit << i);
  }
  *mask_out = mask;
  return true;
}

// TODO: change interface to handle errors!!!
unsigned int UnixKernelRand::p_bits() const {
  Bits m;
  Bits* mask_out = &m;
  return CreateMask(p_threshold_256_, mask_out);
}

unsigned int UnixKernelRand::q_bits() const {
  Bits m;
  Bits* mask_out = &m;
  return CreateMask(q_threshold_256_, mask_out);
}

}  // namespace rappor
