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

namespace rappor {

class ReportList;

class Report {
  // AddString
  // AddInteger?
};

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
// - client doesn't want to change the protobuf for new metric!  Schema is
// application-independent.

// Flow;
//
// Initialize ProtobufEncoder with a schema.
//
// Then send it records.

// TODO: Dump the schema metadata at build time?

enum FieldType {
  kString = 0,
  kOrdinal,
  kBoolean,
};

// TODO: Should be private?
struct Field {
  int id;
  Params params;
  FieldType field_type;
};

class Schema {
 public:
  Schema();
  void AddString(int id, const Params& params);
  void AddOrdinal(int id, const Params& params);
  void AddBoolean(int id, const Params& params);

 private:
  std::vector<Field> fields_;
};

// TODO: Should be private?
struct Value {
  FieldType field_type;
  Bits report;  // encoded report
};

class Record {
 public:
  Record();
  void AddString(int id, const std::string& s);
  void AddOrdinal(int id, int v);
  void AddBoolean(int id, int b);
 private:
  std::vector<Value> values_;
};

class ProtobufEncoder {
 public:
  // TODO: needs rappor::Deps
  ProtobufEncoder(const Schema& schema);

// Shouldn't take encoder, because we need to access the params?
// It can construct internal encoders.

// metric_name, {Field TYPE Params}, const Deps& deps;

// metric_name, {Field1 Type1 Params1, Field2 Type2 Params2}, const Deps& deps;
//
// ClientValues values;
// values.AddString(Field, const string& str);
// values.AddInteger(Field, int i);
//
// Report report;  // protobuf of stuff
// // FAIL if params don't match schema declared to constructor.
// bool ok = protobuf_encoder.Encode(values, &report);
// report.SerializeAsString();

  // Given a string, appends to the given the report list
  // Can raise if the Record is of the wrong type?
  bool Encode(const Record& record, ReportList* report_list);

 private:
  const Schema& schema_;
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

}  // namespace rappor

#endif  // PROTOBUF_ENCODER_H_
