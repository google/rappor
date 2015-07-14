#include <stdio.h>

#include "openssl_impl.h"

// NOTE: See run.sh to compare HMAC and MD5 values with Python.

int main() {
  std::string key("key");
  std::string value("value");
  rappor::Sha256Digest sha256;

  bool result = rappor::Hmac(key, value, sha256);
  printf("result: %d\n", result);
  printf("digest:\n");

  const int n = sizeof(sha256);
  for (int i = 0; i < n; ++i) {
    printf("%02x", sha256[i]);
  }
  printf("\n");

  rappor::Md5Digest md5;

  bool ok = rappor::Md5(value, md5);
  printf("ok: %d\n", ok);

  for (int i = 0; i < sizeof(md5); ++i) {
    printf("%02x", md5[i]);
  }
  printf("\n");

  // how long are secrets?  Probably should be reasonably long
  // ~300 ms for 1M.
  // So then that's 300 ns.  Fast.
  //for (int i = 0; i < 1000000; ++i) {
  //  bool ok = rappor::Md5("01234567890123456789", md5);
  //}

  // 3 seconds for this.  So that's 3 us per HMAC value.
  //
  // For simulation, you can just use 1 byte secrets, so I guess simulation
  // speed isn't really an issue.

  std::string key2("01234567890123456789");
  // It's not that much faster with this small key -- 2.8 seconds.
  //std::string key2("0");

  std::string value2("01234567890123456789");
  //std::string value2("0");

  for (int i = 0; i < 1000000; ++i) {
    bool ok = rappor::Hmac(key2, value2, sha256);
  }
}
