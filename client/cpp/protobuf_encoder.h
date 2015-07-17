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
#include <vector>

#include "encoder.h"  // for Params; maybe that should be in rappor_deps?
#include "rappor_deps.h"  // for dependency injection
#include "rappor.pb.h"

namespace rappor {

class ReportList;

// Chrome example:
//
// https://code.google.com/p/chromium/codesearch#chromium/src/components/rappor/rappor_service.h
//
// example:
// scoped_ptr<Sample> sample = rappor_service->CreateSample(MY_METRIC_TYPE);
// e.g. COARSE_RAPPOR_TYPE
//
// sample->SetStringField("Field1", "some string");
// sample->SetFlagsValue("Field2", SOME|FLAGS);
// rappor_service->RecordSample("MyMetric", sample.Pass());
//
// This will result in a report setting two metrics "MyMetric.Field1" and
// "MyMetric.Field2", and they will both be generated from the same sample,
// to allow for correllations to be computed.
// void RecordSampleObj(const std::string& metric_name,
//                      scoped_ptr<Sample> sample);

// Assumptions:
// - client doesn't want to change the protobuf for new metric!  RecordSchema is
// application-independent.

// Flow;
//
// Initialize ProtobufEncoder with a schema.
//
// Then send it records.

// TODO: Dump the schema metadata at build time?

//enum FieldType {
//  kString = 0,
//  kOrdinal,
//  kBoolean
//};

// TODO: Should be private?
struct Field {
  FieldType field_type;  // matches Value
  int id;  // matches value
  Params params;
};

class RecordSchema {
  friend class ProtobufEncoder;  // needs to read our internal state

 public:
  RecordSchema();
  ~RecordSchema();
  void AddString(int id, const Params& params);
  void AddOrdinal(int id, const Params& params);
  void AddBoolean(int id, const Params& params);

  // Print a user-friendly version.
  //
  // This includes the params.
  bool Print();

 private:
  std::vector<Field> fields_;
};

// Like a tagged union, without really using a union.  TODO: should be private?
struct Value {
  FieldType field_type;  // matches Value
  int id;  // matches value

  // Not using union because of string constructor.  And also the lifetime of
  // rappor::Value objects is very short-lived.
  std::string str;
  int ordinal;
  bool boolean;
};

class Record {
  friend class ProtobufEncoder;  // needs to read our internal state

 public:
  void AddString(int id, const std::string& str);
  void AddOrdinal(int id, int ordinal);
  void AddBoolean(int id, bool boolean);

 private:
  std::vector<Value> values_;
};

class ProtobufEncoder {
 public:
  // TODO: needs rappor::Deps
  ProtobufEncoder(const RecordSchema& schema, const Deps& deps);
  ~ProtobufEncoder();

  // Given a string, appends to the given the report list
  // Can raise if the Record is of the wrong type?
  bool Encode(const Record& record, Report* report);

 private:
  const RecordSchema& schema_;
  std::vector<Encoder*> encoders_;
};

}  // namespace rappor

#endif  // PROTOBUF_ENCODER_H_
