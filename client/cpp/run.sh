#!/bin/bash
#
# Usage:
#   ./run.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

setup() {
  # need libprotobuf-dev for headers to compile against.
  sudo apt-get install protobuf-compiler libprotobuf-dev

  # OpenSSL dev headers
  sudo apt-get install libssl-dev
}

init() {
  mkdir --verbose -p _tmp
}

rappor-sim() {
  make _tmp/rappor_sim
  _tmp/rappor_sim "$@"
}

protobuf-encoder-demo() {
  make _tmp/protobuf_encoder_demo
  _tmp/protobuf_encoder_demo "$@"
}

rappor-sim-demo() {
  rappor-sim 16 2 128 0.25 0.75 0.5 <<EOF
client,cohort,value
c1,1,v1
c1,1,v2
c2,2,v3
c2,2,v4
EOF
}

empty-input() {
  echo -n '' | rappor-sim 58 2 128 .025 0.75 0.5
}

# This outputs an HMAC and MD5 value.  Compare with Python/shell below.

openssl-hash-impl-test() {
  make _tmp/openssl_hash_impl_test
  _tmp/openssl_hash_impl_test "$@"
}

test-hmac-sha256() {
  #echo -n foo | sha256sum
  python -c '
import hashlib
import hmac
import sys

secret = sys.argv[1]
body = sys.argv[2]
m = hmac.new(secret, body, digestmod=hashlib.sha256)
print m.hexdigest()
' "key" "value"
}

test-md5() {
  echo -n value | md5sum
}

# -M: all headers
# -MM: exclude system headers

# -MF: file to write the dependencies to

# -MD: like -M -MF
# -MMD: -MD, but only system headers

# -MP: workaround


deps() {
  # -MM seems like the one we want.
  gcc -I _tmp -MM protobuf_encoder_test.cc unix_kernel_rand_impl.cc
  #gcc -I _tmp -MMD -MP protobuf_encoder_test.cc unix_kernel_rand_impl.cc
}

count() {
  wc -l *.h *.cc | sort -n
}

encoder-demo() {
  make _tmp/encoder_demo && _tmp/encoder_demo
}
cpplint() {
  ../../analysis/cpp/_tmp/cpplint.py "$@"
}

"$@"
