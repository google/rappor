// Copyright 2014 Google Inc. All rights reserved.
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

#include <stdio.h>
#include <time.h>  // time

#include <cassert>  // assert
#include <cstdlib>  // strtol, strtof
#include <iostream>
#include <vector>

#include "encoder.h"
#include "libc_rand_impl.h"
#include "unix_kernel_rand_impl.h"
#include "openssl_hash_impl.h"

// Like atoi, but with basic (not exhaustive) error checking.
bool StringToInt(const char* s, int* result) {
  bool ok = true;
  char* end;  // mutated by strtol

  *result = strtol(s, &end, 10);  // base 10
  // If strol didn't consume any characters, it failed.
  if (end == s) {
    ok = false;
  }
  return ok;
}

// Like atof, but with basic (not exhaustive) error checking.
bool StringToFloat(const char* s, float* result) {
  bool ok = true;
  char* end;  // mutated by strtof

  *result = strtof(s, &end);
  // If strof didn't consume any characters, it failed.
  if (end == s) {
    ok = false;
  }
  return ok;
}

// Copy a report into a string, which can go in a protobuf.
void BitsToString(rappor::Bits b, std::string* output, int num_bytes) {
  output->assign(num_bytes, '\0');
  for (int i = 0; i < num_bytes; ++i) {
    // "little endian" string
    (*output)[i] = b & 0xFF;  // last byte
    b >>= 8;
  }
}

// Print a report, with the most significant bit first.
void PrintBitString(const std::string& s) {
  for (int i = s.size() - 1; i >= 0; --i) {
    unsigned char byte = s[i];
    for (int j = 7; j >= 0; --j) {
      bool bit = byte & (1 << j);
      std::cout << (bit ? "1" : "0");
    }
  }
}

int main(int argc, char** argv) {
  if (argc != 7) {
    rappor::log(
        "Usage: rappor_encode <num bits> <num hashes> <num cohorts> p q f");
    exit(1);
  }

  int num_bits, num_hashes, num_cohorts;
  float prob_p, prob_q, prob_f;

  bool ok1 = StringToInt(argv[1], &num_bits);
  bool ok2 = StringToInt(argv[2], &num_hashes);
  bool ok3 = StringToInt(argv[3], &num_cohorts);

  bool ok4 = StringToFloat(argv[4], &prob_p);
  bool ok5 = StringToFloat(argv[5], &prob_q);
  bool ok6 = StringToFloat(argv[6], &prob_f);

  if (!ok1) {
    rappor::log("Invalid number of bits: '%s'", argv[1]);
    exit(1);
  }
  if (!ok2) {
    rappor::log("Invalid number of hashes: '%s'", argv[2]);
    exit(1);
  }
  if (!ok3) {
    rappor::log("Invalid number of cohorts: '%s'", argv[3]);
    exit(1);
  }
  if (!ok4) {
    rappor::log("Invalid float p: '%s'", argv[4]);
    exit(1);
  }
  if (!ok5) {
    rappor::log("Invalid float q: '%s'", argv[5]);
    exit(1);
  }
  if (!ok6) {
    rappor::log("Invalid float f: '%s'", argv[6]);
    exit(1);
  }

  rappor::Params params(num_bits, num_hashes, num_cohorts, prob_f, prob_p,
                        prob_q);

  //rappor::log("k: %d, h: %d, m: %d", params.num_bits(), params.num_hashes(), params.num_cohorts());
  //rappor::log("f: %f, p: %f, q: %f", prob_f, prob_p, prob_q);

  int num_bytes = params.num_bits() / 8;

  // TODO: Add a flag for
  // - -r libc / kernel
  // - -c openssl / nacl crpto

  rappor::IrrRandInterface* irr_rand;
  if (false) {
    FILE* fp = fopen("/dev/urandom", "r");
    irr_rand = new rappor::UnixKernelRand(fp);
  } else {
    int seed = time(NULL);
    srand(seed);  // seed with nanoseconds
    irr_rand = new rappor::LibcRand();
  }

  std::string line;

  // CSV header
  std::cout << "client,cohort,bloom,prr,irr\n";

  // Consume header line
  std::getline(std::cin, line);
  if (line != "client,cohort,value") {
    rappor::log("Expected CSV header 'client,cohort,value'");
    return 1;
  }

  while (true) {
    std::getline(std::cin, line);  // no trailing newline
    // rappor::log("Got line %s", line.c_str());

    if (line.empty()) {
      break;  // EOF
    }

    size_t comma1_pos = line.find(',');
    if (comma1_pos == std::string::npos) {
      rappor::log("Expected , in line '%s'", line.c_str());
      return 1;
    }
    size_t comma2_pos = line.find(',', comma1_pos + 1);
    if (comma2_pos == std::string::npos) {
      rappor::log("Expected second , in line '%s'", line.c_str());
      return 1;
    }

    // The C++ API substr(pos, length) not (pos, end)

    // everything before comma
    std::string client_str = line.substr(0, comma1_pos);
    // everything between first and second comma.
    // TODO(andychu): Remove unused second column.
    std::string unused = line.substr(comma1_pos + 1, comma2_pos-comma1_pos);
    // everything after
    std::string value = line.substr(comma2_pos + 1);

    rappor::Deps deps(rappor::Md5, client_str /*client_secret*/,
                      rappor::HmacSha256, *irr_rand);

    // For now, construct a new encoder every time.  We could construct one for
    // each client.  We are simulating many clients reporting the same metric,
    // so the encoder ID is constant.
    rappor::Encoder e("metric-name", params, deps);

    // rappor::log("CLIENT %s VALUE %s COHORT %d", client_str.c_str(),
    //             value.c_str(), cohort);

    rappor::Bits bloom;
    rappor::Bits prr;
    rappor::Bits irr;
    bool ok = e._EncodeStringInternal(value, &bloom, &prr, &irr);

    // NOTE: Are there really encoding errors?
    if (!ok) {
      rappor::log("Error encoding string %s", line.c_str());
      break;
    }

    std::string bloom_str;
    BitsToString(bloom, &bloom_str, num_bytes);

    std::string prr_str;
    BitsToString(prr, &prr_str, num_bytes);

    std::string irr_str;
    BitsToString(irr, &irr_str, num_bytes);

    // Output CSV row.

    std::cout << client_str;
    std::cout << ',';
    std::cout << e.cohort();  // cohort the encoder assigned
    std::cout << ',';
    PrintBitString(bloom_str);
    std::cout << ',';
    PrintBitString(prr_str);
    std::cout << ',';
    PrintBitString(irr_str);

    std::cout << "\n";
  }

  // Cleanup
  delete irr_rand;
}
