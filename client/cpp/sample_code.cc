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

//
// This code is copied into README.md, to make sure the sample code actually
// works!
//

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

  int cohort = 99;  // randomly selected from 0 .. num_cohorts-1
  std::string client_secret("secret");  // NOTE: const char* conversion is bad

  rappor::Deps deps(cohort, rappor::Md5, client_secret, rappor::Hmac, irr_rand);
  rappor::Params params = {
    32,   // k = num_bits
    2,    // h = num_hashes
    128,  // m = num_cohorts
    0.25, // probability f for PRR
    0.75, // probability p for IRR
    0.5,  // probability q for IRR
  };
  
  // Instantiate an encoder with params and deps
  rappor::Encoder encoder(params, deps);

  rappor::Bits out;
  assert(encoder.Encode("foo", &out));  // returns false on error

  printf("'foo' encoded with RAPPOR: %x\n", out);

  // Keep calling Encode() on the same 'encoder' instance, or initialize
  // another one if you need different params/deps
}

