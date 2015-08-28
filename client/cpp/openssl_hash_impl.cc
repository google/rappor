#include "openssl_hash_impl.h"
//#include "rappor.h"  // log

#include <string>

#include <openssl/evp.h>  // EVP_sha256
#include <openssl/hmac.h>  // HMAC
#include <openssl/md5.h>  // MD5
#include <openssl/sha.h>  // SHA256_DIGEST_LENGTH

namespace rappor {

// of type HmacFunc in rappor_deps.h
bool Hmac(const std::string& key, const std::string& value,
          std::vector<uint8_t>* output) {
  //log("key %s", key.c_str());
  //log("value %s", value.c_str());

  output->resize(32, 0);

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

// of type Md5Func in rappor_deps.h
bool Md5(const std::string& value, std::vector<uint8_t>* output) {
  output->resize(16, 0);
  // std::string has 'char', OpenSSL wants unsigned char.
  MD5(reinterpret_cast<const unsigned char*>(value.c_str()),
      value.size(), output->data());
  return true;  // OpenSSL MD5 doesn't return an error code
}

}  // namespace rappor
