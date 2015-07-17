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

#include "protobuf_encoder.h"

#include "rappor.pb.h"

namespace rappor {

//
// Schema
//

Schema::Schema() {
}

Schema::~Schema() {
}

void Schema::AddString(int id, const Params& params) {
  Field f;
  f.id = id;
  f.params = params;  // make a copy
  f.field_type = STRING;

  // also makes a copy?  This could be a linked list too.
  fields_.push_back(f);
}

void Schema::AddOrdinal(int id, const Params& params) {
  Field f;
  f.id = id;
  f.params = params;  // make a copy
  f.field_type = ORDINAL;

  // also makes a copy?  This could be a linked list too.
  fields_.push_back(f);
}

void Schema::AddBoolean(int id, const Params& params) {
  Field f;
  f.id = id;
  f.params = params;  // make a copy
  f.field_type = BOOLEAN;

  // also makes a copy?  This could be a linked list too.
  fields_.push_back(f);
}

//
// Record
//

bool Record::AddString(int id, const std::string& s) {
  // TODO: need to encode them
  return true;
}


//
// ProtobufEncoder
//

ProtobufEncoder::ProtobufEncoder(const Schema& schema)
    : schema_(schema) {
  // TODO: instantiate an encoder for each field in the schema
}

// TODO: destroy the encoders
ProtobufEncoder::~ProtobufEncoder() {
  for (size_t i = 0; i < encoders_.size(); ++i) {
    delete encoders_[i];
  }
}

bool ProtobufEncoder::Encode(const Record& record, ReportList* report_list) {
  // TODO: Go through all the values.

  return true;
}

}  // namespace rappor
