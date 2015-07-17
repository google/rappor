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

#ifndef RAPPOR_H_
#define RAPPOR_H_

#include <string>
#include <stdint.h>  // uint64_t

//#include "rappor.pb.h"
#include "rappor_deps.h"  // for dependency injection

namespace rappor {

// (NOTE: leveldb uses this raw-struct style for leveldb::Options)

struct Params {
  // k: size of bloom filter, PRR, and IRR.  0 < k <= 32.
  int num_bits;

  // number of bits set in the Bloom filter ("h")
  int num_hashes;

  // Total number of cohorts ("m").  Note that the cohort assignment is what
  // is used in the client, not m.  We include it here for documentation (it
  // can be unset, unlike the other params.)
  int num_cohorts;

  float prob_f; // for PRR

  float prob_p;  // for IRR
  float prob_q;  // for IRR
};

class Encoder {
 public:
  // TODO:
  // - HmacFunc and Md5Func should be partially computed already
  //   - pass in objects that you can call update() on
  //   - NaCl uses hashblocks.  Can you do that?
  //   - clone state?
  // - Params -> ClientParams?
  //   - this has cohorts, while AnalysisParams has num_cohorts

  Encoder(
      // num_bits, num_hashes, and prob_f are the ones being used
      const Params& params,
      int cohort, Md5Func* md5_func,  // bloom
      const std::string& client_secret, HmacFunc* hmac_func, // PRR
      const IrrRandInterface& irr_rand);  // IRR

  Encoder(const Params& params, const Deps& deps);

  // Check this immediately after instantiating.  We are not using exceptions.
  bool IsValid() const;

  // For simulation use only.
  bool _EncodeInternal(const std::string& value, Bits* bloom_out,
                       Bits* prr_out, Bits* irr_out) const;

  bool Encode(const std::string& value, Bits* irr_out) const;

 private:
  Bits MakeBloomFilter(const std::string& value) const;
  void GetPrrMasks(const std::string& value, Bits* uniform,
                   Bits* f_mask) const;

  const int num_bits_;
  const int num_hashes_;
  const float prob_f_;

  const int cohort_;
  Md5Func* md5_func_;

  const std::string& client_secret_;
  HmacFunc* hmac_func_;

  const IrrRandInterface& irr_rand_;

  int num_bytes_;
  bool is_valid_;
  uint64_t debug_mask_;
};

// For debug logging
void log(const char* fmt, ...);

}  // namespace rappor

#endif  // RAPPOR_H_
