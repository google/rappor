#ifndef OPENSSL_IMPL_H_
#define OPENSSL_IMPL_H_

#include "rappor_deps.h"

namespace rappor {

bool HmacSha256(const std::string& key, const std::string& value,
                std::vector<uint8_t>* output);
bool Md5(const std::string& value, std::vector<uint8_t>* output);

}  // namespace rappor

#endif  // OPENSSL_IMPL_H_
