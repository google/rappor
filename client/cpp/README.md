RAPPOR C++ Client
=================

We provide both a low level and high level client API.  The low level API
implements just the RAPPOR encoding algorithm on strings, with few
dependencies.

The high level API provides wrappers that bundle encoded values into Protocol
Buffer messages.

Build Instructions
------------------

You'll need a C++ compiler, the protobuf compiler, and a library that
implements common hash functions (e.g. OpenSSL).

On Ubuntu or Debian, the protobuf compiler and header files can be installed
with:

    sudo apt-get install protobuf-compiler libprotobuf-dev

OpenSSL can be installed with:

    sudo apt-get install libssl-dev

Test
----

After installing dependencies, You can test it out easily on your machine:

    ./demo.sh quick-cpp

This builds the test harness using a Makefile, and then runs the regtest.sh
simulation.  The last few lines of output will look like this:

    Done running all test instances
    Instances succeeded: 1  failed: 0  running: 0  total: 1
    Wrote _tmp/cpp/results.html
    URL: file:///usr/local/google/home/andychu/git/rappor/_tmp/cpp/results.html

Open the HTML file to see a plot and stats.


SimpleEncoder
-------------

The low level API is `SimpleEncoder`.  You instantitate it with RAPPOR encoding
parameters and application dependencies.  It has a method `Encode()` that takes
an input string (no other types), writes an output parameter of type
`rappor::Bits`, and returns success or failure.

    #include <cassert>

    #include "encoder.h"
    #include "openssl_hash_impl.h"
    #include "unix_kernel_rand_impl.h"
    
    int main(int argc, char** argv) {
      FILE* fp = fopen("/dev/urandom", "r");
      rappor::UnixKernelRand irr_rand(fp);

      int cohort = 99;  // randomly selected from 0 .. num_cohorts-1
      std::string client_secret("secret");  // NOTE: const char* conversion is bad

      rappor::Deps deps(cohort, rappor::Md5, client_secret, rappor::HmacSha256,
                        irr_rand);
      rappor::Params params(
        32,   // num_bits (k)
        2,    // num_hashes (h)
        128,  // num_cohorts (m)
        0.25, // probability f for PRR
        0.75, // probability p for IRR
        0.5   // probability q for IRR
      );

      // Instantiate an encoder with params and deps.
      rappor::Encoder encoder(params, deps);

      // Now use it to encode values.  The 'out' value can be sent over the
      // network.
      rappor::Bits out;
      assert(encoder.Encode("foo", &out));  // returns false on error
      printf("'foo' encoded with RAPPOR: %x\n", out);

      assert(encoder.Encode("bar", &out));  // returns false on error
      printf("'bar' encoded with RAPPOR: %x\n", out);
    }

<!--

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

-->


Dependencies
------------

`rappor::Deps` is a struct-like object that holds the dependencies needed by
the API.

The application must provide the following values:

- cohort: An integer between 0 and `num_cohorts - 1`.  Each value is assigned
  with equal probability to a client process.
- client_secret: A persistent client secret (used for deterministic randomness
  in the PRR, i.e. "memoization" requirement).
- hash_func - string hash function implementation (e.g. MD5)
- hmac_func - HMAC-SHA256 implementation
- irr_rand - randomness for the IRR

We provide an implementation of `hash_func` and `hmac_func` and using OpenSSL.
If your application already has a different implementation of these functions,
you can implement the `HashFunc` and HmacFunc` interfaces.

We provide two example implementations of `irr_rand`: one based on libc
`rand()` (insecure, for demo only), and one based on Unix `/dev/urandom`.

<!--

Protocol Buffer Schema
----------------------

The schema is designed with the assumption that when you add new RAPPOR report
types, you will add a new entry to an application field number `enum`, but you
won't need to add message types.

Instead, there is a single application-independent message that holds all types
of records: `rappor::Report`.

Instead of using protobuf enums, you can also use C / C++ enums.  Protobuf
enums provide some convenience for viewing raw data.

-->

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

Memory Management
-----------------

The `Encoder` instances contain pointers to `Params` and `Deps` instances, but
don't own them.  In the examples, all instances live the stack of `main()`, so
you don't have to worry about them being destroyed.
