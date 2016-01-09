#!/bin/bash
#
# Simple smoke test for the decode-dist tool.  This will fail if your machine
# doesn't have the right R libraries.
#
# Usage:
#   ./test.sh <function name>
#
# Example:
#   ./test.sh write-assoc-testdata       # write data needed for R and C++ tests
#   ./test.sh decode-assoc-R-smoke       # test pure R implementation
#   ./test.sh decode-assoc-cpp-smoke     # test with analysis/cpp/fast_em.cc
#   ./test.sh decode-assoc-cpp-converge  # run for longer with C++
#   ./test.sh decode-assoc-tensorflow

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly RAPPOR_SRC=$(cd $THIS_DIR/.. && pwd)
readonly EM_CPP_EXECUTABLE=$RAPPOR_SRC/analysis/cpp/_tmp/fast_em

source $RAPPOR_SRC/util.sh


decode-dist-help() {
  time $RAPPOR_SRC/bin/decode-dist --help
}

decode-dist() {
  # ./demo.sh quick-python creates these files
  local case_dir=$RAPPOR_SRC/_tmp/python/demo3

  mkdir -p _tmp

  # Uses the ./demo.sh regtest files
  time $RAPPOR_SRC/bin/decode-dist \
    --counts $case_dir/1/case_counts.csv \
    --map $case_dir/case_map.csv \
    --params $case_dir/case_params.csv \
    --output-dir _tmp

  echo
  head _tmp/results.csv 
  echo
  cat _tmp/metrics.json
}

decode-assoc-help() {
  time $RAPPOR_SRC/bin/decode-assoc --help
}

# Clear the R cache for the map files.
clear-cached-files() {
  local dir=$1
  find $dir -name '*.rda' | xargs --no-run-if-empty -- rm --verbose
}

write-assoc-testdata() {
  mkdir -p _tmp

  clear-cached-files _tmp

  cat >_tmp/true_values.csv <<EOF 
domain,flag..HTTPS
google.com,1
google.com,1
google.com,1
google.com,1
google.com,0
yahoo.com,1
yahoo.com,0
bing.com,1
bing.com,1
bing.com,0
EOF

  # NOTE: 64 doesn't work because the Python client is now limited to 32 bits,
  # because of sha1 in PRR.
  local num_bits=32
  local num_hashes=1
  local num_cohorts=128

  local prob_p=0.25
  local prob_q=0.75
  local prob_f=0.5

  # 10 items in the input. 50,000 items is enough to eyeball accuracy of
  # results.
  local assoc_testdata_count=5000

  PYTHONPATH=$RAPPOR_SRC/client/python \
    $RAPPOR_SRC/tests/rappor_sim.py \
    --assoc-testdata $assoc_testdata_count \
    --num-bits $num_bits \
    --num-hashes $num_hashes \
    --num-cohorts $num_cohorts \
    -p $prob_p \
    -q $prob_q \
    -f $prob_f \
    < _tmp/true_values.csv \
    > _tmp/reports.csv

  # Output two bad rows: each row is missing one of the columns.
  cat >_tmp/bad_rows.txt <<EOF
c0,0,10101010,
c0,0,,0
EOF

  # Make CSV file with the header
  cat - _tmp/bad_rows.txt > _tmp/bad_rows.csv <<EOF
client,cohort,domain,flag..HTTPS
EOF

  # Make reports file with bad rows
  cat _tmp/reports.csv _tmp/bad_rows.txt > _tmp/reports_bad_rows.csv

  # Define a string variable and a boolean varaible.
  cat >_tmp/rappor-vars.csv <<EOF 
metric, var, var_type, params
m,domain,string,m_params
m,flag..HTTPS,boolean,m_params
EOF

  cat >_tmp/m_params.csv <<EOF
k,h,m,p,q,f
$num_bits,$num_hashes,$num_cohorts,$prob_p,$prob_q,$prob_f
EOF

  # Add a string with a double quote to test quoting behavior
  cat >_tmp/domain_candidates.csv <<EOF
google.com
yahoo.com
bing.com
q"q
EOF

  # Hash candidates to create map.
  $RAPPOR_SRC/bin/hash-candidates _tmp/m_params.csv \
    < _tmp/domain_candidates.csv \
    > _tmp/domain_map.csv

  banner "Wrote testdata in _tmp"
}

# Helper function to run decode-assoc with testdata.
decode-assoc-helper() {
  local output_dir=$1
  shift

  time $RAPPOR_SRC/bin/decode-assoc \
    --metric-name m \
    --schema _tmp/rappor-vars.csv \
    --reports _tmp/reports.csv \
    --params-dir _tmp \
    --var1 domain \
    --var2 flag..HTTPS \
    --map1 _tmp/domain_map.csv \
    --create-bool-map \
    --max-em-iters 10 \
    --num-cores 2 \
    --output-dir $output_dir \
    --tmp-dir $output_dir \
    "$@"

  head $output_dir/assoc-*

  # Print true values for comparison
  echo
  echo "_tmp/true_values.csv:"
  cat _tmp/true_values.csv
}

# Quick smoke test for R version.
decode-assoc-R-smoke() {
  local output_dir=_tmp/R
  mkdir -p $output_dir
  decode-assoc-helper $output_dir
}

# Test what happens when there are bad rows.
decode-assoc-bad-rows() {
  local output_dir=_tmp/bad
  mkdir -p $output_dir

  # Later flags override earlier ones

  # Reports + bad rows
  decode-assoc-helper $output_dir \
    --reports _tmp/reports_bad_rows.csv \
    --remove-bad-rows \
    "$@"

  # ONLY bad rows
  decode-assoc-helper $output_dir \
    --reports _tmp/bad_rows.csv \
    --remove-bad-rows \
    "$@"
}

build-em-executable() {
  pushd $RAPPOR_SRC/analysis/cpp >/dev/null
  ./run.sh build-fast-em
  popd >/dev/null
}

decode-assoc-cpp-smoke() {
  local output_dir=_tmp/cpp
  mkdir -p $output_dir

  build-em-executable

  decode-assoc-helper $output_dir \
    --em-executable "$EM_CPP_EXECUTABLE" "$@"
}

decode-assoc-cpp-converge() {
  # With the data we have, this converges and exits before 1000 iterations.
  decode-assoc-cpp-smoke --max-em-iters 1000
}

decode-assoc-tensorflow() {
  local output_dir=_tmp/tensorflow
  mkdir -p $output_dir

  decode-assoc-helper $output_dir \
    --em-executable $RAPPOR_SRC/analysis/tensorflow/fast_em.sh "$@"
}

decode-assoc-tensorflow-converge() {
  decode-assoc-tensorflow --max-em-iters 1000
}

"$@"
