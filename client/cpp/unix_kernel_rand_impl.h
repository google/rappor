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

// Unix kernels expose random numbers as files (/dev/random, /dev/urandom,
// etc.).  This uses a file to provide IRR randomness.

#ifndef UNIX_KERNEL_RAND_IMPL_H_
#define UNIX_KERNEL_RAND_IMPL_H_

#include <stdint.h>  // uint8_t
#include <stdio.h>  // FILE*

#include "rappor_deps.h"

namespace rappor {

class UnixKernelRand : public IrrRandInterface {
 public:
  UnixKernelRand(FILE* fp, int num_bits, float p, float q)
      : IrrRandInterface(num_bits, p, q),
        fp_(fp) {
    p_threshold_256_ = static_cast<uint8_t>(p * 256);
    q_threshold_256_ = static_cast<uint8_t>(q * 256);
  }
  virtual ~UnixKernelRand() {}

  virtual bool PMask(Bits* mask_out) const;
  virtual bool QMask(Bits* mask_out) const;

 private:
  bool CreateMask(uint8_t threshold256, Bits* mask_out) const;

  FILE* fp_;  // open device, e.g. /dev/urandom
  uint8_t p_threshold_256_;  // [0, 255) probability threshold
  uint8_t q_threshold_256_;  // [0, 255) probability threshold 
};

}  // namespace rappor

#endif  // UNIX_KERNEL_RAND_IMPL_H_
