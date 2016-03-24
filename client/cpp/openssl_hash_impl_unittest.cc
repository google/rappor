#include <gtest/gtest.h>

#include "openssl_hash_impl.h"


TEST(OpensslHashImplTest, Md5) {
  std::vector<uint8_t> output;
  rappor::Md5("test", &output);
  static const uint8_t ex[] = {
    0x09, 0x8f, 0x6b, 0xcd, 0x46, 0x21, 0xd3, 0x73,
    0xca, 0xde, 0x4e, 0x83, 0x26, 0x27, 0xb4, 0xf6
  };
  std::vector<uint8_t> expected(ex, ex + sizeof(ex));
  ASSERT_EQ(expected, output);
}

TEST(OpensslHashImplTest, HmacSha256) {
  std::vector<uint8_t> output;
  rappor::HmacSha256("key", "value", &output);
  static const uint8_t ex[] = {
    0x90, 0xfb, 0xfc, 0xf1, 0x5e, 0x74, 0xa3, 0x6b,
    0x89, 0xdb, 0xdb, 0x2a, 0x72, 0x1d, 0x9a, 0xec,
    0xff, 0xdf, 0xdd, 0xdc, 0x5c, 0x83, 0xe2, 0x7f,
    0x75, 0x92, 0x59, 0x4f, 0x71, 0x93, 0x24, 0x81, };
  std::vector<uint8_t> expected(ex, ex + sizeof(ex));
  ASSERT_EQ(expected, output);

  // Make sure nulls are handled properly.
  //
  // An empty value with key "key"
  // $ echo -n -e "" | openssl dgst -hmac "key" -sha256 -binary | xxd
  // 00000000: 5d5d 1395 63c9 5b59 67b9 bd9a 8c9b 233a  ]]..c.[Yg.....#:
  // 00000010: 9ded b450 7279 4cd2 32dc 1b74 8326 07d0  ...PryL.2..t.&..
  rappor::HmacSha256("key", "", &output);
  static const uint8_t exempty[] = {
    0x5d, 0x5d, 0x13, 0x95, 0x63, 0xc9, 0x5b, 0x59,
    0x67, 0xb9, 0xbd, 0x9a, 0x8c, 0x9b, 0x23, 0x3a,
    0x9d, 0xed, 0xb4, 0x50, 0x72, 0x79, 0x4c, 0xd2,
    0x32, 0xdc, 0x1b, 0x74, 0x83, 0x26, 0x07, 0xd0
  };
  std::vector<uint8_t> expected_empty(exempty, exempty + sizeof(exempty));
  ASSERT_EQ(expected_empty, output);

  // A single null value with key "key"
  // $ echo -n -e "\x00" | openssl dgst -hmac "key" -sha256 -binary | xxd
  // 00000000: 8a8d fb96 56dc cf21 b7ea 5269 1124 3b75  ....V..!..Ri.$;u
  // 00000010: 68f4 3281 5f1c d43a 4277 1f2d b4aa a525  h.2._..:Bw.-...%
  rappor::HmacSha256("key", std::string("\0", 1), &output);
  static const uint8_t exnull[] = {
    0x8a, 0x8d, 0xfb, 0x96, 0x56, 0xdc, 0xcf, 0x21,
    0xb7, 0xea, 0x52, 0x69, 0x11, 0x24, 0x3b, 0x75,
    0x68, 0xf4, 0x32, 0x81, 0x5f, 0x1c, 0xd4, 0x3a,
    0x42, 0x77, 0x1f, 0x2d, 0xb4, 0xaa, 0xa5, 0x25
  };
  std::vector<uint8_t> expected_null(exnull, exnull + sizeof(exnull));
  ASSERT_EQ(expected_null, output);

  // A null value with something after it, with key "key"
  // $ echo -n -e "\x00a" | openssl dgst -hmac "key" -sha256 -binary | xxd
  // 00000000: 5787 df47 c2c4 8664 5a6a f898 44c3 4636  W..G...dZj..D.F6
  // 00000010: fc5b b78b 1b87 29a0 6ca8 7556 7b75 c05a  .[....).l.uV{u.Z
  rappor::HmacSha256("key", std::string("\0a", 2), &output);
  static const uint8_t exnulltrail[] = {
    0x57, 0x87, 0xdf, 0x47, 0xc2, 0xc4, 0x86, 0x64,
    0x5a, 0x6a, 0xf8, 0x98, 0x44, 0xc3, 0x46, 0x36,
    0xfc, 0x5b, 0xb7, 0x8b, 0x1b, 0x87, 0x29, 0xa0,
    0x6c, 0xa8, 0x75, 0x56, 0x7b, 0x75, 0xc0, 0x5a
  };
  std::vector<uint8_t> expected_null_trailing(
      exnulltrail, exnulltrail + sizeof(exnulltrail));
  ASSERT_EQ(expected_null_trailing, output);
  std::string s = std::string("\0a", 2);
  rappor::HmacSha256("key", s, &output);
  ASSERT_EQ(expected_null_trailing, output);
}

TEST(OpensslHashImplTest, HmacDrbgNist) {
  std::vector<uint8_t> output;
  // Expected output for NIST tests.
  static const uint8_t exnist[] = {
    0xD6, 0x7B, 0x8C, 0x17, 0x34, 0xF4, 0x6F, 0xA3,
    0xF7, 0x63, 0xCF, 0x57, 0xC6, 0xF9, 0xF4, 0xF2,
    0xDC, 0x10, 0x89, 0xBD, 0x8B, 0xC1, 0xF6, 0xF0,
    0x23, 0x95, 0x0B, 0xFC, 0x56, 0x17, 0x63, 0x52,
    0x08, 0xC8, 0x50, 0x12, 0x38, 0xAD, 0x7A, 0x44,
    0x00, 0xDE, 0xFE, 0xE4, 0x6C, 0x64, 0x0B, 0x61,
    0xAF, 0x77, 0xC2, 0xD1, 0xA3, 0xBF, 0xAA, 0x90,
    0xED, 0xE5, 0xD2, 0x07, 0x40, 0x6E, 0x54, 0x03
  };
  std::vector<uint8_t> expected_nist(
      exnist, exnist + sizeof(exnist));

  // NIST test data, from
  // http://csrc.nist.gov/groups/ST/toolkit/documents/Examples/HMAC_DRBG.pdf
  // p.148, requested security strength 128, Requested hash algorithm SHA-256
  output.resize(64);
  rappor::HmacDrbg(
    std::string(
        "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09"
        "\x0A\x0B\x0C\x0D\x0E\x0F\x10\x11\x12\x13"
        "\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D"
        "\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27"
        "\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31"
        "\x32\x33\x34\x35\x36\x20\x21\x22\x23\x24"
        "\x25\x26\x27", 63), // provided_data
    "", &output);
  ASSERT_EQ(expected_nist, output);

  // Since in our use case we concatenate the key and value
  // to produce the provided_data portion of the DRBG, let's
  // split the above key into key|value as an additional
  // test case.
  output.resize(64);
  rappor::HmacDrbg(
    std::string(
        "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09"
        "\x0A\x0B\x0C\x0D\x0E\x0F\x10\x11\x12\x13"
        "\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D"
        "\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27", 40),
    std::string(
        "\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31"
        "\x32\x33\x34\x35\x36\x20\x21\x22\x23\x24"
        "\x25\x26\x27", 23), // provided_data
    &output);
  ASSERT_EQ(expected_nist, output);
}

TEST(OpensslHashImplTest, HmacDrbgTextStrings) {
  std::vector<uint8_t> output;
  output.resize(30);
  rappor::HmacDrbg("key", "value", &output);  // Truncated to 30 bytes.
  static const uint8_t ex[] = {
    0x89, 0xD7, 0x1B, 0xB8, 0xA3, 0x7D, 0x80, 0xC2,
    0x6E, 0x63, 0x9C, 0xBD, 0x68, 0xF3, 0x60, 0x7A,
    0xA9, 0x4D, 0xEE, 0xF4, 0x25, 0xA7, 0xAF, 0xBB,
    0xF8, 0xD0, 0x09, 0x92, 0xAF, 0x92
  };
  std::vector<uint8_t> expected(ex, ex + sizeof(ex));
  ASSERT_EQ(expected, output);
}

int main(int argc, char **argv) {
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
