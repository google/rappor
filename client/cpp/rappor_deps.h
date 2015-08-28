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

#ifndef RAPPOR_DEPS_H_
#define RAPPOR_DEPS_H_

#include <stdint.h>  // for uint32_t
#include <string>

namespace rappor {

// rappor::Bits type is used for Bloom Filter, PRR, and IRR
typedef uint32_t Bits;

// NOTE: If using C++11 (-std=c++0x), you could use something like this instead
// of std::string output.
//
// typedef std::array<unsigned char, 32> Sha256Digest;

// rappor::Encoder needs a hash function for the bloom filter, and an HMAC
// function for the PRR.

typedef bool Md5Func(const std::string& value, std::string* output);
typedef bool HmacFunc(const std::string& key, const std::string& value,
                      std::string* output);

// Interface that the encoder use to generate randomness for the IRR.
// Applications should implement this based on their platform and requirements.
class IrrRandInterface {
 public:
  virtual ~IrrRandInterface() {}
  // Compute a bitmask with each bit set to 1 with probability 'prob'.
  // Returns false if there is an error.
  virtual bool GetMask(float prob, int num_bits, Bits* mask_out) const = 0;
};

class Deps {
 public:
  Deps(int cohort, Md5Func* md5_func, const std::string& client_secret,
       HmacFunc* hmac_func, const IrrRandInterface& irr_rand)
      : cohort_(cohort),
        md5_func_(md5_func),
        client_secret_(client_secret),
        hmac_func_(hmac_func),
        irr_rand_(irr_rand) {
  }

  int cohort_;  // bloom
  Md5Func* md5_func_;  // bloom
  const std::string& client_secret_;  // PRR
  HmacFunc* hmac_func_;  // PRR
  const IrrRandInterface& irr_rand_;  // IRR
};

}  // namespace rappor

#endif  // RAPPOR_DEPS_H_

