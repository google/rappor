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

void Record::AddString(int id, const std::string& str) {
  Value v;
  v.field_type = STRING;
  v.id = id;
  v.str = str;

  values_.push_back(v);
}

void Record::AddOrdinal(int id, int ordinal) {
  Value v;
  v.field_type = ORDINAL;
  v.id = id;
  v.ordinal = ordinal;

  values_.push_back(v);
}

void Record::AddBoolean(int id, bool boolean) {
  Value v;
  v.field_type = BOOLEAN;
  v.id = id;
  v.boolean = boolean;

  values_.push_back(v);
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

  size_t expected_num_values = schema_.fields_.size();
  size_t num_values = record.values_.size();
  if (expected_num_values != num_values) {
    rappor::log("Expected %d values, got %d", expected_num_values, num_values);
    return false;
  }

  for (size_t i = 0; i < num_values; ++i) {
    std::string input_word;  // input to RAPPOR algorithm
    const Value& v = record.values_[i];

    // Sanity check: fields should be added to the Record in the same order
    // they were "declared" in the RecordSchema.
    int expected_field_id = schema_.fields_[i].id;
    if (v.id != expected_field_id) {
      rappor::log("Expected field ID %d, got %d", expected_field_id, v.id);
      return false;
    }

    FieldType expected_field_type = schema_.fields_[i].field_type;
    if (v.field_type != expected_field_type) {
      rappor::log("Expected field type %d, got %d", expected_field_type,
          v.field_type);
      return false;
    }

    switch (v.field_type) {
      case STRING:
        input_word.assign(v.str);
        break;
      case ORDINAL:
        //input_word.assign(record.ordinals_[i]);
        input_word.assign("TODO");
        break;
      case BOOLEAN:
        input_word.assign(v.boolean ? "\x01" : "\x00");
        break;
      default:
        rappor::log("Unexpected field type %d", v.field_type);
        assert(0);  // programming error
    }
    Bits irr;
    bool ok = encoders_[i]->Encode(input_word, &irr);
    report->add_field_id(v.id);
    report->add_bits(irr);

    if (!ok) {
      rappor::log("Failed to encode variable %d, aborting record", i);
      return false;
    }
  }

  return true;
}

}  // namespace rappor
