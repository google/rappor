RAPPOR C++ Client
=================

We provide both a low level and high level client API.  The low level API
implements just the RAPPOR encoding algorithm on strings, with few
dependencies.

The high level API provides wrappers
Most applications should be able to use the high level API, but 

The low level API is `SimpleEncoder`.  You instantitate it with RAPPOR encoding
parameters and application dependencies.  It has a method `Encode()` that takes
only strings, and returns a rappor::Bits (uint32\_t).


    #include <cassert>

    #include "encoder.h"

    rappor::Deps deps(...);
    rappor::Params params = { ... };
    
    // This can encode strings
    rappor::SimpleEncoder e(params, deps);

    rappor::Bits encoded;

    assert(e.Encode("foo", &encoded));  // returns false on error


The high level API lets you 1) create records with multiple observations and 2)
encode them together as a serialized protocol buffer.

    #include <cassert>
    #include "protobuf_encoder.h"

    rappor::Deps deps(...);
    rappor::Params params = { ... };

    // "Declare" a schema.
    rappor::RecordSchema schema;
    schema.AddString(kNameField, params);
    schema.AddOrdinal(kSexField, params);  // male or female

    // Create an encoder that will serialize records of this schema as a
    // protocol buffer.
    rappor::ProtobufEncoder e(schema, deps);

    // Instantiate a record.
    rappor::Record record;
    record.AddString(kNameField, "alice");
    record.AddString(kSexField, kFemale);

    // Create a serialized report.
    rappor::Report report1;  // protocol buffer type
    assert(e.Encode(record, &report1));

    // Instantiate a record.
    rappor::Record record;
    record.AddString(kNameField, "alice");
    record.AddString(kSexField, kFemale);

    // Create a serialized report.
    rappor::Report report1;  // protocol buffer type
    assert(e.Encode(record, &report1));

For typed single variables, there are also three additional wrappers over
ProtobufEncoder: StringEncoder, BooleanEncoder, and OrdinalEncoder.

    rappor::BooleanEncoder e(kFieldUsingSsl, params, deps);

    rappor::Report report;
    assert(e.Encode(true, &report));  // encode boolean

Dependencies
------------

`rappor::Deps` is a struct-like object that holds the dependencies needed by
both the high level and low level API.

The application must provide the following two values:

- cohort: An integer between 0 and `num_cohorts - 1`.  Each value is assigned
  with equal probability to a client process.
- client_secret: A persistent client secret (used for the PRR "memoization"
  requirement).

It must provide the following functions / classes:

- md5_func - MD5 implementation
- hmac_func_ - HMAC-SHA256 implementation
- irr_rand_ - Randomness used for the IRR.  We provide two example
  implementations: one based on libc `rand()` and one based on Unix
  `/dev/urandom`.


Protocol Buffer Schema
----------------------

The schema is designed with the assumption that when you add new RAPPOR report
types, you will add a new entry to an application field number `enum`, but you
won't need to add message types.

Instead, there is a single application-independent message that holds all types
of records: `rappor::Report`.

Instead of using protobuf enums, you can also use C / C++ enums.  Protobuf
enums provide some convenience for viewing raw data.

Error Handling
--------------

Note that incorrect usage of the `SimpleEncoder` and `Protobuf` constructors
may cause *runtime assertions* (using `assert()`).  For example, if
Params.num\_bits is more than 32, the process will crash.

Encoders should be initialized at application startup, with constant
parameters, so this type of error should be seen early.

The various `Encode()` members do *not* raise assertions.  If those are used in
correctly, then the return value will be `false` to indicate an error.  These
failures should be handled by the application.

