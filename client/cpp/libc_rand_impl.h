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

// A RAPPOR random implementation using libc's rand().
//
// IMPORTANT: This is for demo /simulation purposes only.  Use a better random
// function in production applications.

#ifndef LIBC_RAND_IMPL_H_
#define LIBC_RAND_IMPL_H_

#include "rappor_deps.h"

namespace rappor {

class LibcRand : public IrrRandInterface {
 public:
  virtual ~LibcRand() {}

  virtual bool GetMask(float prob, int num_bits, Bits* mask_out) const;
};

}  // namespace rappor

#endif  // LIBC_RAND_IMPL_H_
