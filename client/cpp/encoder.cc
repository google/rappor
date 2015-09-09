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

#include "encoder.h"

#include <stdio.h>
#include <stdarg.h>  // va_list, etc.

#include <cassert>  // assert
#include <vector>

namespace rappor {

void log(const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
  fprintf(stderr, "\n");
}

//
// Functions for debugging
//

static void PrintHex(const std::vector<uint8_t>& h) {
  for (size_t i = 0; i < h.size(); ++i) {
    fprintf(stderr, "%02x", h[i]);
  }
  fprintf(stderr, "\n");
}

// We use 1 *byte* of a HMAC-SHA256 value per BIT to generate the PRR.  SHA256
// has 32 bytes, so the max is 32 bits.
static const int kMaxBits = 32;

// Can't be more than the number of bytes in MD5.
static const int kMaxHashes = 16;

// Probabilities should be in the interval [0.0, 1.0].
static void CheckValidProbability(float prob, const char* var_name) {
  if (prob < 0.0f || prob > 1.0f) {
    log("%s should be between 0.0 and 1.0 (got %.2f)", var_name, prob);
    assert(false);
  }
}

// Used to 1) turn cohort into a string, and 2) Turn raw bits into a string.
// Return by value since it's small.
static std::string ToBigEndian(uint32_t u) {
  std::string result(4, '\0');

  // rely on truncation to char
  result[0] = u >> 24;
  result[1] = u >> 16;
  result[2] = u >> 8;
  result[3] = u;

  return result;
}

static const char* kHmacCohortPrefix = "\x00";
static const char* kHmacPrrPrefix = "\x01";


//
// Encoder
//

Encoder::Encoder(const std::string& encoder_id, const Params& params, 
                 const Deps& deps)
    : encoder_id_(encoder_id),
      params_(params),
      deps_(deps),
      cohort_str_() {

  if (params_.num_bits_ <= 0) {
    log("num_bits must be positive");
    assert(false);
  }
  if (params_.num_hashes_ <= 0) {
    log("num_hashes must be positive");
    assert(false);
  }
  if (params_.num_cohorts_ <= 0) {
    log("num_cohorts must be positive");
    assert(false);
  }
  // Check Maximum values.
  if (params_.num_bits_ > kMaxBits) {
    log("num_bits (%d) can't be greater than %d", params_.num_bits_, kMaxBits);
    assert(false);
  }
  if (params_.num_hashes_ > kMaxHashes) {
    log("num_hashes (%d) can't be greater than %d", params_.num_hashes_,
        kMaxHashes);
    assert(false);
  }
  int m = params_.num_cohorts_;
  if ((m & (m - 1)) != 0) {
    log("num_cohorts (%d) must be a power of 2 (and not 0)", m);
    assert(false);
  }
  // TODO: check max cohorts?

  CheckValidProbability(params_.prob_f_, "prob_f");
  CheckValidProbability(params_.prob_p_, "prob_p");
  CheckValidProbability(params_.prob_q_, "prob_q");

  std::vector<uint8_t> sha256;
  if (!deps_.hmac_func_(deps_.client_secret_, kHmacCohortPrefix, &sha256)) {
    log("HMAC failed");
    assert(false);
  }
  assert(sha256.size() == kMaxBits);

  // e.g. 128 cohorts is 0x80 - 1 = 0x7f

  // TODO: Fill in cohort_ and cohort_str_.
  // Interpret first 4 bytes of sha256 as a uint32_t.
  uint32_t c = *(reinterpret_cast<uint32_t*>(sha256.data()));
  uint32_t cohort_mask = m - 1;
  cohort_ = c & cohort_mask;
  cohort_str_ = ToBigEndian(cohort_);

  //log("secret: %s", deps_.client_secret_.c_str());
  //log("c: %u", c);
  //log("num_cohorts: %d", m);
  //log("cohort mask: %x", cohort_mask);
  //log("cohort_: %d", cohort_);
}

bool Encoder::MakeBloomFilter(const std::string& value, Bits* bloom_out) const {
  const int num_bits = params_.num_bits_;
  const int num_hashes = params_.num_hashes_;

  Bits bloom = 0;

  // 4 byte cohort string + true value
  std::string hash_input(cohort_str_ + value);

  // First do hashing.
  std::vector<uint8_t> hash_output;
  deps_.hash_func_(hash_input, &hash_output);

  // Error check
  if (hash_output.size() < static_cast<size_t>(num_hashes)) {
    rappor::log("Hash function didn't return enough bytes");
    return false;
  }

  // To determine which bit to set in the bloom filter, use a byte of the MD5.
  for (int i = 0; i < num_hashes; ++i) {
    int bit_to_set = hash_output[i] % num_bits;
    bloom |= 1 << bit_to_set;
  }

  *bloom_out = bloom;
  return true;
}

// Helper function for PRR
bool Encoder::GetPrrMasks(Bits bits, Bits* uniform_out, Bits* f_mask_out) const {
  // Create HMAC(secret, value), and use its bits to construct f and uniform
  // bits.
  std::vector<uint8_t> sha256;
  // NOTE: Do we need kHmacPrrPrefix here?  Why different prefixes if the keyys
  // are different?  The HMAC key for the cohort is the client secret; the
  // HMAC key for the PRR is client secret + encoder ID.
  std::string hmac_key = deps_.client_secret_ + encoder_id_;
  std::string hmac_value = ToBigEndian(bits);
  deps_.hmac_func_(hmac_key, hmac_value, &sha256);
  if (sha256.size() != kMaxBits) {  // sanity check
    return false;
  }

  // We should have already checked this.
  assert(params_.num_bits_ <= kMaxBits);

  uint8_t threshold128 = static_cast<uint8_t>(params_.prob_f_ * 128);

  Bits uniform = 0;
  Bits f_mask = 0;

  for (int i = 0; i < params_.num_bits_; ++i) {
    uint8_t byte = sha256[i];

    uint8_t u_bit = byte & 0x01;  // 1 bit of entropy
    uniform |= (u_bit << i);  // maybe set bit in mask

    uint8_t rand128 = byte >> 1;  // 7 bits of entropy
    uint8_t noise_bit = (rand128 < threshold128);
    f_mask |= (noise_bit << i);  // maybe set bit in mask
  }

  *uniform_out = uniform;
  *f_mask_out = f_mask;
  return true;
}

bool Encoder::_EncodeBitsInternal(Bits bits, Bits* prr_out, Bits* irr_out) const {
  // Compute Permanent Randomized Response (PRR).
  Bits uniform;
  Bits f_mask;
  if (!GetPrrMasks(bits, &uniform, &f_mask)) {
    rappor::log("GetPrrMasks failed");
    return false;
  }

  Bits prr = (bits & ~f_mask) | (uniform & f_mask);
  *prr_out = prr;

  // Compute Instantaneous Randomized Response (IRR).

  // NOTE: These can fail if say a read() from /dev/urandom fails.
  Bits p_bits;
  Bits q_bits;
  if (!deps_.irr_rand_.GetMask(params_.prob_p_, params_.num_bits_, &p_bits)) {
    rappor::log("PMask failed");
    return false;
  }
  if (!deps_.irr_rand_.GetMask(params_.prob_q_, params_.num_bits_, &q_bits)) {
    rappor::log("QMask failed");
    return false;
  }

  Bits irr = (p_bits & ~prr) | (q_bits & prr);
  *irr_out = irr;

  return true;
}

bool Encoder::_EncodeStringInternal(const std::string& value, Bits* bloom_out,
    Bits* prr_out, Bits* irr_out) const {
  Bits bloom;
  if (!MakeBloomFilter(value, &bloom)) {
    rappor::log("Bloom filter calculation failed");
    return false;
  }
  *bloom_out = bloom;

  return _EncodeBitsInternal(bloom, prr_out, irr_out);
}

bool Encoder::EncodeBits(Bits bits, Bits* irr_out) const {
  Bits unused_prr;
  return _EncodeBitsInternal(bits, &unused_prr, irr_out);
}

bool Encoder::EncodeString(const std::string& value, Bits* irr_out) const {
  Bits unused_bloom;
  Bits unused_prr;
  return _EncodeStringInternal(value, &unused_bloom, &unused_prr, irr_out);
}

}  // namespace rappor
