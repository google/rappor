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

// Sample code for encoder.cc.
//
// This is the code in README.md.  It's here to make sure it actually builds
// and runs.

#include <cassert>  // assert

#include "encoder.h"
#include "openssl_hash_impl.h"
#include "unix_kernel_rand_impl.h"

int main(int argc, char** argv) {
  // Suppress unused variable warnings
  (void) argc;
  (void) argv;

  FILE* fp = fopen("/dev/urandom", "r");
  rappor::UnixKernelRand irr_rand(fp);

  rappor::Deps deps(rappor::Md5, "client-secret", rappor::HmacSha256,
                    irr_rand);
  rappor::Params params(32,    // num_bits (k)
                        2,     // num_hashes (h)
                        128,   // num_cohorts (m)
                        0.25,  // probability f for PRR
                        0.75,  // probability p for IRR
                        0.5);  // probability q for IRR

  const char* encoder_id = "metric-name";
  rappor::Encoder encoder(encoder_id, params, deps);

  // Now use it to encode values.  The 'out' value can be sent over the
  // network.
  rappor::Bits out;
  assert(encoder.EncodeString("foo", &out));  // returns false on error
  printf("'foo' encoded with RAPPOR: %0x, cohort %d\n", out, encoder.cohort());

  // Raw bits
  assert(encoder.EncodeBits(0x123, &out));  // returns false on error
  printf("0x123 encoded with RAPPOR: %0x, cohort %d\n", out, encoder.cohort());
}

