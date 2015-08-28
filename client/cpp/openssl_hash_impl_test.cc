#include <stdint.h>  // for uint32_t
#include <stdio.h>
#include <string>
#include <vector>

#include "openssl_hash_impl.h"

// NOTE: See run.sh to compare HMAC and MD5 values with Python.

int main() {
  std::string key("key");
  std::string value("value");
  std::vector<uint8_t> sha256;

  bool ok1 = rappor::Hmac(key, value, &sha256);
  printf("ok: %d\n", ok1);
  printf("digest:\n");

  for (size_t i = 0; i < sha256.size(); ++i) {
    printf("%02x", sha256[i]);
  }
  printf("\n");

  std::vector<uint8_t> md5;

  bool ok2 = rappor::Md5(value, &md5);
  printf("ok: %d\n", ok2);

  for (size_t i = 0; i < md5.size(); ++i) {
    printf("%02x", md5[i]);
  }
  printf("\n");
}
