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

// of type HashFunc in rappor_deps.h
bool Md5(const std::string& value, std::vector<uint8_t>* output) {
  output->resize(MD5_DIGEST_LENGTH, 0);

  // std::string has 'char', OpenSSL wants unsigned char.
  MD5(reinterpret_cast<const unsigned char*>(value.c_str()),
      value.size(), output->data());
  return true;  // OpenSSL MD5 doesn't return an error code
}

}  // namespace rappor
