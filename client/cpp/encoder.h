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

// RAPPOR encoder.
//
// See README.md and encoder_demo.cc for an example.

#ifndef RAPPOR_H_
#define RAPPOR_H_

#include <string>

#include "rappor_deps.h"  // for dependency injection

namespace rappor {

// For debug logging
void log(const char* fmt, ...);

// RAPPOR encoding parameters.
class Params {
 public:
  Params(int num_bits, int num_hashes, int num_cohorts,
         float prob_f, float prob_p, float prob_q)
      : num_bits_(num_bits),
        num_hashes_(num_hashes),
        num_cohorts_(num_cohorts),
        prob_f_(prob_f),
        prob_p_(prob_p),
        prob_q_(prob_q) {
  }

  // Accessors
  int num_bits() { return num_bits_; }
  int num_hashes() { return num_hashes_; }
  int num_cohorts() { return num_cohorts_; }
  float prob_f() { return prob_f_; }
  float prob_p() { return prob_p_; }
  float prob_q() { return prob_q_; }

 private:
  friend class Encoder;

  // k: size of bloom filter, PRR, and IRR.  0 < k <= 32.
  int num_bits_;

  // number of bits set in the Bloom filter ("h")
  int num_hashes_;

  // Total number of cohorts ("m").  Note that the cohort assignment is what
  // is used in the client, not m.  We include it here for documentation (it
  // can be unset, unlike the other params.)
  int num_cohorts_;

  float prob_f_;  // noise probability for PRR, quantized to 1/128

  float prob_p_;  // noise probability for IRR, quantized to 1/128
  float prob_q_;  // noise probability for IRR, quantized to 1/128
};

// Encoder: take client values and transform them with the RAPPOR privacy
// algorithm.
class Encoder {
 public:
  // Note that invalid parameters cause runtime assertions in the constructor.
  // Encoders are intended to be created at application startup with constant
  // arguments, so errors should be caught early.

  // encoder_id: A unique ID for this encoder -- typically the name of the
  //   metric being encoded, so that different metrics have different PRR
  //   mappings.
  // params: RAPPOR encoding parameters, which affect privacy and decoding.
  //   (held by reference; it must outlive the Encoder)
  // deps: application-supplied dependencies.
  //   (held by reference; it must outlive the Encoder)
  Encoder(const std::string& encoder_id, const Params& params,
          const Deps& deps);

  // Encode raw bits (represented as an integer), setting output parameter
  // irr_out.  Only valid when the return value is 'true' (success).
  bool EncodeBits(const Bits bits, Bits* irr_out) const;

  // Encode a string, setting output parameter irr_out.  Only valid when the
  // return value is 'true' (success).
  bool EncodeString(const std::string& value, Bits* irr_out) const;
  // For use with HmacDrbg hash function and any num_bits divisible by 8.
  bool EncodeString(const std::string& value,
                    std::vector<uint8_t>* irr_out) const;

  // For testing/simulation use only.
  bool _EncodeBitsInternal(const Bits bits, Bits* prr_out, Bits* irr_out)
    const;
  bool _EncodeStringInternal(const std::string& value, Bits* bloom_out,
                             Bits* prr_out, Bits* irr_out) const;

  // Accessor for the assigned cohort.
  uint32_t cohort() { return cohort_; }
  // Set a cohort manually, if previously generated.
  void set_cohort(uint32_t cohort);

 private:
  bool MakeBloomFilter(const std::string& value, Bits* bloom_out) const;
  bool MakeBloomFilter(const std::string& value,
                       std::vector<uint8_t>* bloom_out) const;
  bool GetPrrMasks(const Bits bits, Bits* uniform, Bits* f_mask) const;

  // static helper function for initialization
  static uint32_t AssignCohort(const Deps& deps, int num_cohorts);

  const std::string encoder_id_;
  const Params& params_;
  const Deps& deps_;
  uint32_t cohort_;
  std::string cohort_str_;
};

}  // namespace rappor

#endif  // RAPPOR_H_
