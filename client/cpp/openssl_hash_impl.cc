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
          std::string* output) {
  //log("key %s", key.c_str());
  //log("value %s", value.c_str());

  unsigned char openssl_out[32];

  // A pointer on success, or NULL on failure.
  unsigned char* result = HMAC(
      EVP_sha256(), key.c_str(), key.size(),
      // std::string has 'char', OpenSSL wants unsigned char.
      reinterpret_cast<const unsigned char*>(value.c_str()),
      value.size(),
      openssl_out,
      NULL);

  
  if (result != NULL) {
    output->assign(reinterpret_cast<const char*>(openssl_out), sizeof(openssl_out));
    return true;
  } else {
    return false;
  }
}

// of type Md5Func in rappor_deps.h
bool Md5(const std::string& value, std::string* output) {
  unsigned char openssl_out[16];

  // std::string has 'char', OpenSSL wants unsigned char.
  MD5(reinterpret_cast<const unsigned char*>(value.c_str()),
      value.size(), openssl_out);
  output->assign(reinterpret_cast<const char*>(openssl_out), sizeof(openssl_out));
  return true;  // OpenSSL MD5 doesn't return an error code
}

}  // namespace rappor
