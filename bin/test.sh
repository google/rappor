#!/bin/bash
#
# Simple smoke test for the decode-dist tool.  This will fail if your machine
# doesn't have the right R libraries.
#
# Usage:
#   ./test.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

decode-dist() {
  # ./demo.sh quick-python creates these files
  local case_dir=../_tmp/python/demo3

  mkdir -p _tmp

  # Uses the ./demo.sh regtest files
  time ./decode-dist \
    --counts $case_dir/1/case_counts.csv \
    --map $case_dir/case_map.csv \
    --params $case_dir/case_params.csv \
    --output-dir _tmp

  echo
  head _tmp/results.csv 
  echo
  cat _tmp/metrics.json
}

"$@"
