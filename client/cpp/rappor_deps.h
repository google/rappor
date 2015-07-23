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

#include <stdint.h>  // uint64_t
#include <string>

namespace rappor {

// rappor::Bits type is used for Bloom Filter, PRR, and IRR
typedef uint64_t Bits; 

// NOTE: If using C++11 (-std=c++0x), it's safer to do this:
// typedef std::array<unsigned char, 32> Sha256Digest;

typedef unsigned char Md5Digest[16];
typedef unsigned char Sha256Digest[32];

// rappor:Encoder needs an MD5 function for the bloom filter, and an HMAC
// function for the PRR.
//
// And a random function for the IRR.
//   NOTE: libc rand returns a float between 0 and 1.
// Maybe you just need to return p_bits and q_bits.

// NOTE: is md5 always sufficient?  Maybe you should have a generic hash.
// string -> string?  But you need to know how many bits there are.
// num_hashes * log2(num_bits) == 2 * log2(8) = 6, or 2 * log2(128) = 14.
//
// TODO: Do these really fail?  I don't think md5 does.

typedef bool Md5Func(const std::string& value, Md5Digest output);
typedef bool HmacFunc(const std::string& key, const std::string& value,
                      Sha256Digest output);

// Interface that the encoder requires.  Applications should implement this
// based on their platform and requirements.
class IrrRandInterface {
 public:
  virtual ~IrrRandInterface() {}
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

