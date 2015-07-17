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

#include "rappor_deps.h"  // for dependency injection

namespace rappor {

// For debug logging
void log(const char* fmt, ...);

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
  Encoder(const Params& params, const Deps& deps);

  // For simulation use only.
  bool _EncodeInternal(const std::string& value, Bits* bloom_out,
                       Bits* prr_out, Bits* irr_out) const;

  bool Encode(const std::string& value, Bits* irr_out) const;

 private:
  Bits MakeBloomFilter(const std::string& value) const;
  void GetPrrMasks(const std::string& value, Bits* uniform,
                   Bits* f_mask) const;

  const Params& params_;
  const Deps& deps_;
};

}  // namespace rappor

#endif  // RAPPOR_H_
