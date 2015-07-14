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

#ifndef LIBC_RAND_IMPL_H_
#define LIBC_RAND_IMPL_H_

#include "rappor_deps.h"

namespace rappor {

// call this once per application.
void LibcRandGlobalInit();

class LibcRand : public IrrRandInterface {
 public:
  LibcRand(int num_bits, float p, float q);
  virtual ~LibcRand() {}

  virtual bool PMask(Bits* mask_out) const;
  virtual bool QMask(Bits* mask_out) const;

 private:
  Bits CreateMask(int rand_threshold) const;

  int p_rand_threshold_;  // [0, RAND_MAX) probability threshold
  int q_rand_threshold_;  // [0, RAND_MAX) probability threshold 
};

}  // namespace rappor

#endif  // LIBC_RAND_IMPL_H_
