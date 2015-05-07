#!/bin/bash
#
# Simple smoke test for the analysis_tool.R file.  Can test if you have all the
# right R libraries and so forth.
#
# Usage:
#   ./test.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

analysis-tool() {
  # Expects to be run from this dir, and changes to repo root.
  pushd ../../

  local regtest_dir=_tmp/regtest

  mkdir -p _tmp

  # Uses the ./demo.sh regtest files
  time analysis/R/analysis_tool.R \
    --counts $regtest_dir/demo1/1/case_counts.csv \
    --map $regtest_dir/demo1/case_map.csv \
    --config $regtest_dir/demo1/case_params.csv  \
    --output_dir _tmp

  cat _tmp/results.csv 

  popd
}

"$@"
