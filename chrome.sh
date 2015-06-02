#!/bin/bash
#
# Usage:
#   ./chrome.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

# Feature of googlesource.com.
download() {
  local url='https://chromium.googlesource.com/chromium/src.git/+/master/components/rappor/byte_vector_utils_unittest.cc?format=TEXT'
  # Pretty weird that this is wrapped in base64!
  curl $url | base64 --decode
}

"$@"
