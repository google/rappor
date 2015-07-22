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
// Sample code for protobuf_encoder.cc.
//

#include <cassert>  // assert
#include <cstdlib>  // strtol, strtof
#include <iostream>
#include <stdio.h>
#include <vector>

#include "protobuf_encoder.h"
#include "rappor.pb.h"
#include "libc_rand_impl.h"
#include "openssl_hash_impl.h"

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

// Global constants
const rappor::Params kParams4 = {
  .num_bits = 8, .num_hashes = 2, .num_cohorts = 128,
  .prob_f = 0.25f, .prob_p = 0.5f, .prob_q = 0.75f
};

// Initalize and return some bundle of encoders.
// Keyed by ID?
//
// PROBLEM: There are 4 types of encoders.  You could have them inherit from
// the same interface?
// The EncodeString can return false ...

void InitRappor() {
}

// Given schema ID / encoder ID, prints parameters.  Map file association lives
// somewhere else.
//
// Equivalent of metrics.csv and params.csv.  Although params can be inline.
//
// Have an alternative --flag that does this.

void PrintRapporConfig() {
}

// Simulate the body of the program.
void EncodeExample() {
}


int main(int argc, char** argv) {

  // NOTE: This isn't valid C++.  Designated initializers are a C99 feature
  // that GCC and Clang allow, but warn about.
  // Chrome only has it in third_party, not in their own code.

  rappor::Params params = {
    .num_bits = 8, .num_hashes = 2, .num_cohorts = 128,
    .prob_f = 0.25f, .prob_p = 0.75f, .prob_q = 0.5f
  };

  rappor::Params params2 = {
    .num_bits = 32, .num_hashes = 2, .num_cohorts = 128,
    .prob_f = 0.25f, .prob_p = 0.75f, .prob_q = 0.5f
  };

  // TODO: seed it
  rappor::LibcRand libc_rand(params.num_bits, params.prob_p, params.prob_q);

  // TODO: assert that params passed to rand match?
  // Or pass all params to rand?
  rappor::LibcRand libc_rand2(params2.num_bits, params2.prob_p, params2.prob_q);

  int cohort = 5;  // random integer in range [0, 512)

  rappor::Deps deps(cohort, rappor::Md5, "client_secret",
                    rappor::Hmac, libc_rand);

  rappor::Deps deps2(cohort, rappor::Md5, "client_secret",
                     rappor::Hmac, libc_rand2);

  const std::string line("foo");

  // Collection of reports.  Reports encoded records.
  rappor::ReportList report_list;

  const int NAME_FIELD = 1;
  const int ADDRESS_FIELD = 2;

  // Set up schema with two fields.
  rappor::RecordSchema s;
  s.AddString(NAME_FIELD, params);
  s.AddString(ADDRESS_FIELD, params);

  // Instantiate encoder.
  rappor::ProtobufEncoder protobuf_encoder(s, deps);

  // Construct a recorder, and then encode it into a new entry in the report
  // list.
  rappor::Record record;
  record.AddString(NAME_FIELD, "foo");
  //record.AddBoolean(ADDRESS_FIELD, false);  // error
  record.AddString(ADDRESS_FIELD, "bar");
  //record.AddBoolean(ADDRESS_FIELD, false);  // error

  rappor::Report* report = report_list.add_report();
  if (!protobuf_encoder.Encode(record, report)) {
    rappor::log("Error encoding record %s", line.c_str());
    return 1;
  }

  rappor::log("----------");

  rappor::Report* report2 = report_list.add_report();
  rappor::StringEncoder string_encoder(NAME_FIELD, params2, deps2);
  if (!string_encoder.EncodeString("STRING", report2)) {
    rappor::log("Error encoding string %s", line.c_str());
    return 1;
  }

  rappor::log("report2 [%s]", report2->DebugString().c_str());

  rappor::log("----------");

  rappor::Report* report3 = report_list.add_report();
  rappor::OrdinalEncoder ordinal_encoder(NAME_FIELD, params, deps);
  if (!ordinal_encoder.EncodeOrdinal(10, report3)) {
    rappor::log("Error encoding ordinal %s", line.c_str());
    return 1;
  }

  rappor::log("----------");

  rappor::log("RecordReport [%s]", report->DebugString().c_str());

  rappor::log("ReportList [%s]", report_list.DebugString().c_str());
}
