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
// RecordSchema
//

RecordSchema::RecordSchema() {
}

RecordSchema::~RecordSchema() {
}

void RecordSchema::AddString(int id, const Params& params) {
  Field f;
  f.field_type = STRING;
  f.id = id;
  f.params = params;  // copy?

  fields_.push_back(f);
}

void RecordSchema::AddOrdinal(int id, const Params& params) {
  Field f;
  f.field_type = ORDINAL;
  f.id = id;
  f.params = params;  // copy?

  fields_.push_back(f);
}

void RecordSchema::AddBoolean(int id, const Params& params) {
  Field f;
  f.field_type = BOOLEAN;
  f.id = id;
  f.params = params;  // copy?

  fields_.push_back(f);
}

//
// Record
//

bool Record::AddString(int id, const std::string& s) {
  field_types_.push_back(STRING);
  ids_.push_back(id);
  strings_.push_back(s);
  return true;
}


//
// ProtobufEncoder
//

ProtobufEncoder::ProtobufEncoder(const RecordSchema& schema, const Deps& deps)
    : schema_(schema) {
  // On construction, instantiate an encoder for each field in the schema.
  for (size_t i = 0; i < schema.fields_.size(); ++i) {
    const Params& params = schema.fields_[i].params;
    encoders_.push_back(new Encoder(params, deps));
  }
}

ProtobufEncoder::~ProtobufEncoder() {
  for (size_t i = 0; i < encoders_.size(); ++i) {
    delete encoders_[i];
  }
}

bool ProtobufEncoder::Encode(const Record& record, Report* report) {
  // Go through all the values.  Convert them to strings to be encoded, and
  // then push them through the correct encoder.
  //
  // TODO: Check that the record matches the schema in number of fields and
  // field number.

  for (size_t i = 0; i < record.ids_.size(); ++i) {
    std::string input_word;  // input to RAPPOR algorithm
    switch (record.field_types_[i]) {
      case STRING:
        input_word.assign(record.strings_[i]);
        break;
      //case ORDINAL:
      //  input_word.assign(record.ordinals_[i]);
      //  break;
      case BOOLEAN:
        input_word.assign(record.booleans_[i] ? "\x01" : "\x00");
        break;
    }
    Bits irr;
    bool ok = encoders_[i]->Encode(input_word, &irr);
    report->add_bits(irr);

    if (!ok) {
      rappor::log("Failed to encode variable %d, aborting record", i);
      return false;
    }
  }

  return true;
}

}  // namespace rappor
