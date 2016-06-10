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
#include "openssl_hash_impl.h"

#include <assert.h>
#include <stdio.h>
#include <stdarg.h>  // va_list, etc.
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
    log("%s should be between 0.0 and 1.0 inclusive (got %.2f)", var_name,
        prob);
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

uint32_t Encoder::AssignCohort(const Deps& deps, int num_cohorts) {
  std::vector<uint8_t> sha256;
  if (!deps.hmac_func_(deps.client_secret_, kHmacCohortPrefix, &sha256)) {
    log("HMAC failed");
    assert(false);
  }

  // Either we are using SHA256 to have exactly 32 bytes,
  // or we're using HmacDrbg for any number of bytes.
  if ((sha256.size() == kMaxBits)
      || (deps.hmac_func_ == rappor::HmacDrbg)) {
    // Hash size ok.
  } else {
    log("Bad hash size.");
    assert(false);
  }

  // Interpret first 4 bytes of sha256 as a uint32_t.
  uint32_t c = *(reinterpret_cast<uint32_t*>(sha256.data()));
  // e.g. for 128 cohorts, 0x80 - 1 = 0x7f
  uint32_t cohort_mask = num_cohorts - 1;
  return c & cohort_mask;
}

Encoder::Encoder(const std::string& encoder_id, const Params& params,
                 const Deps& deps)
    : encoder_id_(encoder_id),
      params_(params),
      deps_(deps),
      cohort_(AssignCohort(deps, params.num_cohorts_)),
      cohort_str_(ToBigEndian(cohort_)) {

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
  if (deps_.hmac_func_ == rappor::HmacDrbg) {
    // Using HmacDrbg
    if (params_.num_bits_ % 8 != 0) {
      log("num_bits (%d) must be divisible by 8 when using HmacDrbg.",
          params.num_bits_);
      assert(false);
    }
  } else {
    // Using SHA256
    if (params_.num_bits_ > kMaxBits) {
        log("num_bits (%d) can't be greater than %d", params_.num_bits_,
            kMaxBits);
        assert(false);
    }
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
    log("Hash function didn't return enough bytes");
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

// Write a Bloom filter into a vector of bytes, used for num_bits > 32.
bool Encoder::MakeBloomFilter(const std::string& value,
                              std::vector<uint8_t>* bloom_out) const {
  const int num_bits = params_.num_bits_;
  const int num_hashes = params_.num_hashes_;

  bloom_out->resize(params_.num_bits_ / 8, 0);

  // Generate the hash.
  std::vector<uint8_t> hash_output;
  deps_.hash_func_(std::string(cohort_str_ + value), &hash_output);

  // Check that we have enough bytes of hash available.
  int exponent = 0;
  int bytes_needed = 0;
  while ((1 << exponent) < num_bits) {
    exponent++;
  }
  bytes_needed = ((exponent - 1) / 8) + 1;
  if (bytes_needed > 4) {
    log("Can only use 4 bytes of hash at a time, needed %d "
        "to address %d bits.", bytes_needed, num_bits);
    return false;
  }
  if (hash_output.size() < static_cast<size_t>(bytes_needed * num_hashes)) {
    log("Hash function returned %d bytes, but we needed "
        "%d bytes * %d hashes. Choose lower num_hashes or "
        "a different hash function.",
        hash_output.size(), bytes_needed, num_hashes);
    return false;
  }

  // To determine which bit to set in the Bloom filter, use 1 or more
  // bytes of the MD5.
  int hash_byte = 0;
  for (int i = 0; i < num_hashes; ++i) {
    int bit_to_set = 0;
    for (int j = 0; j < bytes_needed; ++j) {
      bit_to_set |= hash_output[hash_byte] << (j * 8);
      ++hash_byte;
    }
    bit_to_set %= num_bits;
    // Start at end of array to be consistent with the Bits implementation.
    int index = (bloom_out->size() - 1) - (bit_to_set / 8);
    (*bloom_out)[index] |= 1 << (bit_to_set % 8);
  }
  return true;
}

// Helper method for PRR
bool Encoder::GetPrrMasks(const Bits bits, Bits* uniform_out,
                          Bits* f_mask_out) const {
  // Create HMAC(secret, value), and use its bits to construct f_mask and
  // uniform bits.
  std::vector<uint8_t> sha256;

  std::string hmac_value = kHmacPrrPrefix + encoder_id_ + ToBigEndian(bits);

  deps_.hmac_func_(deps_.client_secret_, hmac_value, &sha256);
  if (sha256.size() != kMaxBits) {  // sanity check
    return false;
  }

  // We should have already checked this.
  if (params_.num_bits_ > kMaxBits) {
    log("num_bits exceeds maximum.");
    assert(false);
  }

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

bool Encoder::_EncodeBitsInternal(const Bits bits, Bits* prr_out,
                                  Bits* irr_out) const {
  // Compute Permanent Randomized Response (PRR).
  Bits uniform;
  Bits f_mask;
  if (!GetPrrMasks(bits, &uniform, &f_mask)) {
    log("GetPrrMasks failed");
    return false;
  }

  Bits prr = (bits & ~f_mask) | (uniform & f_mask);
  *prr_out = prr;

  // Compute Instantaneous Randomized Response (IRR).

  // NOTE: These can fail if say a read() from /dev/urandom fails.
  Bits p_bits;
  Bits q_bits;
  if (!deps_.irr_rand_.GetMask(params_.prob_p_, params_.num_bits_, &p_bits)) {
    log("PMask failed");
    return false;
  }
  if (!deps_.irr_rand_.GetMask(params_.prob_q_, params_.num_bits_, &q_bits)) {
    log("QMask failed");
    return false;
  };

  Bits irr = (p_bits & ~prr) | (q_bits & prr);
  *irr_out = irr;

  return true;
}

bool Encoder::_EncodeStringInternal(const std::string& value, Bits* bloom_out,
    Bits* prr_out, Bits* irr_out) const {
  if (!MakeBloomFilter(value, bloom_out)) {
    log("Bloom filter calculation failed");
    return false;
  }
  return _EncodeBitsInternal(*bloom_out, prr_out, irr_out);
}

bool Encoder::EncodeBits(const Bits bits, Bits* irr_out) const {
  Bits unused_prr;
  return _EncodeBitsInternal(bits, &unused_prr, irr_out);
}

bool Encoder::EncodeString(const std::string& value, Bits* irr_out) const {
  Bits unused_bloom;
  Bits unused_prr;
  return _EncodeStringInternal(value, &unused_bloom, &unused_prr, irr_out);
}

static uint8_t shifted(const Bits& bits, const int& index) {
  // For an array of bytes, select the appopriate byte from a 4-byte
  // integer value. Bytes are enumerated in big-endian order, i.e.
  // index = 0 is the MSB, index = 3 is the LSB.
  int shift = 8 * (3 - (index % 4)); // Byte 0 shifts by 24 bits, 1 by 16, etc.
  return (uint8_t)((bits >> shift) & 0xFF);  // Return the correct byte.
}

bool Encoder::EncodeString(const std::string& value,
                           std::vector<uint8_t>* irr_out) const {
  std::vector<uint8_t> bloom_out;
  std::vector<uint8_t> hmac_out;
  std::vector<uint8_t> uniform;
  std::vector<uint8_t> f_mask;
  const int num_bits = params_.num_bits_;

  uniform.resize(num_bits / 8, 0);
  f_mask.resize(num_bits / 8, 0);
  irr_out->resize(num_bits / 8, 0);

  // Set bloom_out.
  if (!MakeBloomFilter(value, &bloom_out)) {
    log("Bloom filter calculation failed");
    return false;
  }

  // Set hmac_out.
  hmac_out.resize(num_bits);  // Signal to HmacDrbg about desired output size.
  // Call HmacDrbg
  std::string hmac_value =  kHmacPrrPrefix + encoder_id_;
  for (int i = 0; i < bloom_out.size(); ++i) {
    hmac_value.append(reinterpret_cast<char *>(&bloom_out[i]), 1);
  }
  deps_.hmac_func_(deps_.client_secret_, hmac_value, &hmac_out);
  if (hmac_out.size() != num_bits) {
    log("Needed %d bytes from Hmac function, received %d bytes.",
        num_bits, hmac_out.size());
    return false;
  }

  // We'll be using 7 bits of each byte of the MAC as our random
  // number for the f_mask.
  uint8_t threshold128 = static_cast<uint8_t>(params_.prob_f_ * 128);

  // Construct uniform and f_mask bitwise.
  for (int i = 0; i < num_bits; i++) {
    uint8_t byte = hmac_out[i];
    uint8_t u_bit = byte & 0x01;  // 1 bit of entropy.
    int vector_index = (num_bits - 1 - i) / 8;
    uint8_t rand128 = byte >> 1;  // 7 bits of entropy.
    uint8_t noise_bit = (rand128 < threshold128);
    uniform[vector_index] |= (u_bit << (i % 8));
    f_mask[vector_index] |= (noise_bit << (i % 8));
  }

  for (int i = 0; i < bloom_out.size(); i++) {
    Bits p_bits;
    Bits q_bits;
    uint8_t prr;
    prr = (bloom_out[i] & ~f_mask[i]) | (uniform[i] & f_mask[i]);
    // GetMask operates on Uint32, so we generate a new p_bits every 4
    // bytes, and use each of its bytes once.
    if (i % 4 == 0) {
      // Need new p_bits, q_bits values to work with.
      if (!deps_.irr_rand_.GetMask(params_.prob_p_, 32, &p_bits)) {
        log("PMask failed");
        return false;
      }
      if (!deps_.irr_rand_.GetMask(params_.prob_q_, 32, &q_bits)) {
        log("QMask failed");
        return false;
      }
    }
    (*irr_out)[i] = (shifted(p_bits, i) & ~prr)
        | (shifted(q_bits, i) & prr);
  }
}

void Encoder::set_cohort(uint32_t cohort) {
  cohort_ = cohort;
  cohort_str_ = ToBigEndian(cohort_);
}

}  // namespace rappor
