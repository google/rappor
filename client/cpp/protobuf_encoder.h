// Copyright 2015 Google Inc. All rights reserved.
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

#ifndef PROTOBUF_ENCODER_H_
#define PROTOBUF_ENCODER_H_

#include <string>
#include <stdint.h>  // uint64_t

#include "encoder.h"
#include "rappor_deps.h"  // for dependency injection

namespace rappor {

class ReportList;

class Report {
  // AddString
  // AddInteger?
};

class ProtobufEncoder {
 public:
  ProtobufEncoder(const char* metric_name, const Encoder& encoder);

  // Given a string, appends to the given the report list
  bool Encode(const Report& report, ReportList* report_list);
 private:
};

// Encoder -> StringEncoder?

// TODO: This should encompass association?
//
// ProtobufEncoder should take
//
// { var_name, type, params }+
//
// Shared params:
//
// cohort, md5_func, client_secret, hmac_func, irr_rand
//
// Then it will instantiate its own encoders internally.
//
// RapporDeps -- what does
//
// ClientInfo: cohort, client_secret
// RapporDeps: md5_func, hmac_func, irr_rand
//
// ClientInfo, Params, Deps
//
// ClientInfo, { name, type, params }+ Deps

class VarType {
};

// a variable reported across time
struct RapporVar {
  std::string var_name;  // sent with ReportList
  VarType var_type;  // protobuf STRING, ENUM, etc.?  Or does it matter?
                     // this can be out of band?
  Params p;  // raw params, or protobuf?
};

}  // namespace rappor

#endif  // PROTOBUF_ENCODER_H_
