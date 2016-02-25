#!/bin/bash
usage() {
echo "

 Simple smoke test for the decode-dist tool.  This will fail if your machine
 doesn't have the right R libraries.

 Usage:
   ./test.sh <function name>

 Example:
   ./test.sh decode-assoc-R-smoke       # test pure R implementation
   ./test.sh decode-assoc-cpp-smoke     # test with analysis/cpp/fast_em.cc
   ./test.sh decode-assoc-cpp-converge  # run for longer with C++
   ./test.sh decode-assoc-tensorflow
"
}

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly RAPPOR_SRC=$(cd $THIS_DIR/.. && pwd)
readonly EM_CPP_EXECUTABLE=$RAPPOR_SRC/analysis/cpp/_tmp/fast_em

source $RAPPOR_SRC/util.sh

readonly ASSOC_TESTDATA_DIR=_tmp/decode-assoc-test
readonly DIST_TESTDATA_DIR=_tmp/decode-dist-test

# Clear the R cache for the map files.
clear-cached-files() {
  local dir=$1
  find $dir -name '*.rda' | xargs --no-run-if-empty -- rm --verbose
}

write-dist-testdata() {
  local input_dir=$DIST_TESTDATA_DIR/input

  mkdir -p $input_dir

  clear-cached-files $DIST_TESTDATA_DIR

  # Right now, we copy a case from regtest.sh.  (./demo.sh quick-python creates
  # just this case)
  local case_dir=$RAPPOR_SRC/_tmp/python/demo3

  cp --verbose $case_dir/1/case_counts.csv $input_dir/counts.csv
  cp --verbose $case_dir/case_map.csv $input_dir/map.csv
  cp --verbose $case_dir/case_params.csv $input_dir/params.csv
}

decode-dist() {
  write-dist-testdata

  local output_dir=$DIST_TESTDATA_DIR

  local input_dir=$DIST_TESTDATA_DIR/input

  # Uses the ./demo.sh regtest files
  time $RAPPOR_SRC/bin/decode-dist \
    --counts $input_dir/counts.csv \
    --map $input_dir/map.csv \
    --params $input_dir/params.csv \
    --output-dir $output_dir

  echo
  head $output_dir/results.csv 
  echo
  cat $output_dir/metrics.json
}

write-assoc-testdata() {
  # 'build' has intermediate build files, 'input' is the final input to the
  # decode-assoc tool.
  local build_dir=$ASSOC_TESTDATA_DIR/build
  local input_dir=$ASSOC_TESTDATA_DIR/input

  mkdir -p $build_dir $input_dir

  clear-cached-files $ASSOC_TESTDATA_DIR

  cat >$build_dir/true_values.csv <<EOF 
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

  local num_bits=8
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
    < $build_dir/true_values.csv \
    > $input_dir/reports.csv

  # Output two bad rows: each row is missing one of the columns.
  cat >$build_dir/bad_rows.txt <<EOF
c0,0,10101010,
c0,0,,0
EOF

  # Make CSV file with the header
  cat - $build_dir/bad_rows.txt > $input_dir/bad_rows.csv <<EOF
client,cohort,domain,flag..HTTPS
EOF

  # Make reports file with bad rows
  cat $input_dir/reports.csv $build_dir/bad_rows.txt > $input_dir/reports_bad_rows.csv

  # Define a string variable and a boolean varaible.
  cat >$input_dir/rappor-vars.csv <<EOF 
metric, var, var_type, params
m,domain,string,m_params
m,flag..HTTPS,boolean,m_params
EOF

  cat >$input_dir/m_params.csv <<EOF
k,h,m,p,q,f
$num_bits,$num_hashes,$num_cohorts,$prob_p,$prob_q,$prob_f
EOF

  # Add a string with a double quote to test quoting behavior
  cat >$build_dir/domain_candidates.csv <<EOF
google.com
yahoo.com
bing.com
q"q
EOF

  # Hash candidates to create map.
  $RAPPOR_SRC/bin/hash-candidates $input_dir/m_params.csv \
    < $build_dir/domain_candidates.csv \
    > $input_dir/domain_map.csv

  banner "Wrote testdata in $input_dir (intermediate files in $build_dir)"
}

# Helper function to run decode-assoc with testdata.
decode-assoc-helper() {
  write-assoc-testdata

  local output_dir=$1
  shift

  local build_dir=$ASSOC_TESTDATA_DIR/build
  local input_dir=$ASSOC_TESTDATA_DIR/input

  time $RAPPOR_SRC/bin/decode-assoc \
    --metric-name m \
    --schema $input_dir/rappor-vars.csv \
    --reports $input_dir/reports.csv \
    --params-dir $input_dir \
    --var1 domain \
    --var2 flag..HTTPS \
    --map1 $input_dir/domain_map.csv \
    --create-bool-map \
    --max-em-iters 10 \
    --num-cores 2 \
    --output-dir $output_dir \
    --tmp-dir $output_dir \
    "$@"

  head $output_dir/assoc-*

  # Print true values for comparison
  echo
  echo "$build_dir/true_values.csv:"
  cat "$build_dir/true_values.csv"
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

if test $# -eq 0 ; then
  usage
else
  "$@"
fi
