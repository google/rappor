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

// A RAPPOR random implementation using bytes from a file like /dev/urandom or
// /dev/random.

#ifndef UNIX_KERNEL_RAND_IMPL_H_
#define UNIX_KERNEL_RAND_IMPL_H_

#include <stdint.h>  // uint8_t
#include <stdio.h>  // FILE*

#include "rappor_deps.h"

namespace rappor {

class UnixKernelRand : public IrrRandInterface {
 public:
  explicit UnixKernelRand(FILE* fp)
      : fp_(fp) {
  }
  virtual ~UnixKernelRand() {}

  virtual bool GetMask(float prob, int num_bits, Bits* mask_out) const;

 private:
  FILE* fp_;  // open device, e.g. /dev/urandom
};

}  // namespace rappor

#endif  // UNIX_KERNEL_RAND_IMPL_H_
