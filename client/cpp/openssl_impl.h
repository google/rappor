#ifndef OPENSSL_IMPL_H_
#define OPENSSL_IMPL_H_

#include "rappor_deps.h"

namespace rappor {

// Prototypes using typedefs
bool Hmac(const std::string& key, const std::string& value,
          Sha256Digest output);
bool Md5(const std::string& value, Md5Digest output);

}  // namespace rappor

#endif  // OPENSSL_IMPL_H_
