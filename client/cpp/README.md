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


Encoder
-------

The low level API is `Encoder`.  You instantiatate it with RAPPOR encoding
parameters and application dependencies.  It has a method `EncodeString()` that
takes an input string (no other types), sets an output parameter of type
`rappor::Bits`, and returns success or failure.

```cpp
#include <cassert>

#include "encoder.h"
#include "openssl_hash_impl.h"
#include "unix_kernel_rand_impl.h"

int main(int argc, char** argv) {
  FILE* fp = fopen("/dev/urandom", "r");
  rappor::UnixKernelRand irr_rand(fp);

  rappor::Deps deps(rappor::Md5, "client-secret", rappor::HmacSha256,
                    irr_rand);
  rappor::Params params(32,    // num_bits (k)
                        2,     // num_hashes (h)
                        128,   // num_cohorts (m)
                        0.25,  // probability f for PRR
                        0.75,  // probability p for IRR
                        0.5);  // probability q for IRR

  const char* encoder_id = "metric-name";
  rappor::Encoder encoder(encoder_id, params, deps);

  // Now use it to encode values.  The 'out' value can be sent over the
  // network.
  rappor::Bits out;
  assert(encoder.EncodeString("foo", &out));  // returns false on error
  printf("'foo' encoded with RAPPOR: %0x, cohort %d\n", out, encoder.cohort());

  // Raw bits
  assert(encoder.EncodeBits(0x123, &out));  // returns false on error
  printf("0x123 encoded with RAPPOR: %0x, cohort %d\n", out, encoder.cohort());
}
```

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

Error Handling
--------------

Note that incorrect usage of the `SimpleEncoder` and `Protobuf` constructors
may cause *runtime assertions* (using `assert()`).  For example, if
Params.num\_bits is more than 32, the process will crash.

Encoders should be initialized at application startup, with constant
parameters, so this type of error should be seen early.

The various `Encode()` members do *not* raise assertions.  If those are used
incorrectly, then the return value will be `false` to indicate an error.  These
failures should be handled by the application.

Memory Management
-----------------

The `Encoder` instances contain pointers to `Params` and `Deps` instances, but
don't own them.  In the examples, all instances live the stack of `main()`, so
you don't have to worry about them being destroyed.
