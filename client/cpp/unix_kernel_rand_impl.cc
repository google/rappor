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

namespace rappor {

const int kMaxBitWidth = 32;  // also in encoder.cc

bool UnixKernelRand::GetMask(float prob, int num_bits, Bits* mask_out) const {
  uint8_t rand_buf[kMaxBitWidth];
  size_t num_elems = fread(&rand_buf, sizeof(uint8_t), num_bits, fp_);
  if (num_elems != static_cast<size_t>(num_bits)) {  // fread error
    return false;
  }
  uint8_t threshold_256 = static_cast<uint8_t>(prob * 256);

  Bits mask = 0;
  for (int i = 0; i < num_bits; ++i) {
    uint8_t bit = (rand_buf[i] < threshold_256);
    mask |= (bit << i);
  }
  *mask_out = mask;
  return true;
}

}  // namespace rappor
