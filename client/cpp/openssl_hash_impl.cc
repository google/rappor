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

#include "openssl_hash_impl.h"

#include <stdlib.h>
#include <string>

#include <openssl/evp.h>  // EVP_sha256
#include <openssl/hmac.h>  // HMAC
#include <openssl/md5.h>  // MD5
#include <openssl/sha.h>  // SHA256_DIGEST_LENGTH

namespace rappor {

// of type HmacFunc in rappor_deps.h
bool HmacSha256(const std::string& key, const std::string& value,
          std::vector<uint8_t>* output) {
  output->resize(SHA256_DIGEST_LENGTH, 0);

  // Returns a pointer on success, or NULL on failure.
  unsigned char* result = HMAC(
      EVP_sha256(), key.c_str(), key.size(),
      // std::string has 'char', OpenSSL wants unsigned char.
      reinterpret_cast<const unsigned char*>(value.c_str()),
      value.size(),
      output->data(),
      NULL);

  return (result != NULL);
}

// Of type HmacFunc in rappor_deps.h
//
// The length of the passed-in output vector determines how many
// bytes are returned.
//
// No reseed operation, but recommended reseed_interval <= 2^48 updates.
// Since we're seeding for each value and typically don't need
// so many bytes, we should be OK.
bool HmacDrbg(const std::string& key, const std::string& value,
              std::vector<uint8_t>* output) {
  const unsigned char k_array[] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
  };
  std::string v;
  std::vector<uint8_t> temp_output;
  int num_bytes = output->size();
  if (num_bytes == 0) {
    // By default return 32 bytes for Uint32 applications.
    num_bytes = 32;
  }

  v.append(32u, 0x01);
  temp_output.resize(32, 0);

  std::string temp_str(v);
  temp_str.append(std::string("\0", 1));
  // provided_data is key|value.
  temp_str.append(key);
  temp_str.append(value);

  output->resize(0);

  // Instantiate.
  if (!HmacSha256(std::string(k_array, k_array + 32), temp_str, &temp_output)) {
    return false;
  }
  std::string k(temp_output.begin(), temp_output.end());
  if (!HmacSha256(k, v, &temp_output)) {
    return false;
  }
  v = std::string(temp_output.begin(), temp_output.end());
  if (!HmacSha256(k, v + std::string("\1", 1) + key + value, &temp_output)) {
    return false;
  }
  k = std::string(temp_output.begin(), temp_output.end());
  if (!HmacSha256(k, v, &temp_output)) {
    return false;
  }
  v = std::string(temp_output.begin(), temp_output.end());

  while (output->size() < num_bytes) {
    // Generate.
    if (!HmacSha256(k, v, &temp_output)) {
      return false;
    }
    v = std::string(temp_output.begin(), temp_output.end());
    output->insert(output->end(), temp_output.begin(), temp_output.end());
  }
  output->resize(num_bytes);
  return true;
}

// of type HashFunc in rappor_deps.h
bool Md5(const std::string& value, std::vector<uint8_t>* output) {
  output->resize(MD5_DIGEST_LENGTH, 0);

  // std::string has 'char', OpenSSL wants unsigned char.
  MD5(reinterpret_cast<const unsigned char*>(value.c_str()),
      value.size(), output->data());
  return true;  // OpenSSL MD5 doesn't return an error code
}

}  // namespace rappor
