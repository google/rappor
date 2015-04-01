#!/bin/bash
#
# Run end-to-end tests in parallel.
#
# Usage:
#   ./regtest.sh <function name>

# Examples:
#
# $ export NUM_PROCS=20  # 12 by default
# $ ./regtest.sh run-all  # run all reg tests with 20 parallel processes
#
# At the end, it will print an HTML summary.

# To run a subset of tests or debug a specific test case, use the 'run-seq'
# function:
#
# $ ./regtest.sh run-seq demo-exp  # Sequential run, matches 1 case
# $ ./regtest.sh run-seq demo-     # Sequential run, matches multiple cases
#
# The first argument to run-seq is a regex in 'grep -E' format.  (Detail: Don't
# use $ in the pattern, since it matches the whole spec line and not just the
# test case name.)

# Future speedups:
# - Reuse the same input -- come up with naming scheme based on params
# - Reuse the same maps -- ditto, rappor library can cache it

set -o nounset
set -o pipefail
set -o errexit

. util.sh

readonly THIS_DIR=$(dirname $0)
readonly REPO_ROOT=$THIS_DIR
readonly CLIENT_DIR=$REPO_ROOT/client/python
readonly REGTEST_DIR=_tmp/regtest

# All the Python tools need this
export PYTHONPATH=$CLIENT_DIR

readonly NUM_SPEC_COLS=${NUM_PROCS:-13}

# TODO: Get num cpus
readonly NUM_PROCS=${NUM_PROCS:-12}


# Run a single test case, specified by a line of the test spec.
# This is a helper function for 'run-all'.

_run-one-case() {
  local test_case_id=$1

  # input params
  local dist=$2
  local num_unique_values=$3
  local num_clients=$4
  local values_per_client=$5

  # RAPPOR params
  local num_bits=$6
  local num_hashes=$7
  local num_cohorts=$8
  local p=$9
  local q=${10}
  local f=${11}  # need curly braces to get 10th arg

  # map params
  local num_additional=${12}
  local to_remove=${13}

  # NOTE: NUM_SPEC_COLS == 13

  local case_dir=$REGTEST_DIR/$test_case_id
  mkdir --verbose -p $case_dir

  banner "Saving spec"

  # The arguments are the test case spec
  echo "$@" > $case_dir/spec.txt

  banner "Generating input"

  tests/gen_sim_input.py \
    -d $dist \
    -n $num_clients \
    -r $num_unique_values \
    -c $values_per_client \
    -o $case_dir/case.csv

  # NOTE: Have to name inputs and outputs by the test case name
  # _tmp/test/t1
  #./demo.sh gen-sim-input-demo $dist $num_clients $num_unique_values

  banner "Running RAPPOR client"

  tests/rappor_sim.py \
    --bloombits $num_bits \
    --hashes $num_hashes \
    --cohorts $num_cohorts \
    -p $p \
    -q $q \
    -f $f \
    -i $case_dir/case.csv \
    -o $case_dir/out.csv

  banner "Constructing candidates"

  # Reuse demo.sh function
  ./demo.sh print-candidates \
    $case_dir/case_true_inputs.txt $num_unique_values \
    $num_additional "$to_remove" \
    > $case_dir/case_candidates.txt

  banner "Hashing candidates to get 'map'"

  analysis/tools/hash_candidates.py \
    $case_dir/case_params.csv \
    < $case_dir/case_candidates.txt \
    > $case_dir/case_map.csv

  banner "Summing bits to get 'counts'"

  analysis/tools/sum_bits.py \
    $case_dir/case_params.csv \
    < $case_dir/out.csv \
    > $case_dir/case_counts.csv

  local out_dir=$REGTEST_DIR/${test_case_id}_report
  mkdir --verbose -p $out_dir

  # Input prefix, output dir
  tests/analyze.R -t "Test case: $test_case_id" "$case_dir/case" $out_dir
}

# Like _run-once-case, but log to a file.
_run-one-case-logged() {
  local test_case_id=$1

  local case_dir=$REGTEST_DIR/$test_case_id
  mkdir --verbose -p $case_dir

  log "Started '$test_case_id' -- logging to $case_dir/log.txt"
  _run-one-case "$@" >$case_dir/log.txt 2>&1
  log "Test case $test_case_id done"
}

show-help() {
  tests/gen_sim_input.py || true
  tests/rappor_sim.py -h || true
}

make-summary() {
  local dir=$1

  tests/make_summary.py $dir > $dir/rows.html

  pushd $dir >/dev/null

  cat ../../tests/regtest.html \
    | sed -e '/TABLE_ROWS/ r rows.html' \
    > results.html

  popd >/dev/null

  log "Wrote $dir/results.html"
  log "URL: file://$PWD/$dir/results.html"
}

# Helper to parse spec input with xargs
multi() {
  xargs -n $NUM_SPEC_COLS --no-run-if-empty --verbose "$@"
}

test-error() {
  local spec_regex=$1
  log "Some cases failed, or none matched pattern '$spec_regex'"
  exit 1
}

# Assuming the spec file, write a list of test case names (first column).  This
# is read by make_summary.py.
write-test-cases() {
  cut -d ' ' -f 1 $REGTEST_DIR/spec-list.txt > $REGTEST_DIR/test-cases.txt
}

# run-all should take regex?
run-seq() {
  local spec_regex=$1  # grep -E format on the spec

  local spec_list=$REGTEST_DIR/spec-list.txt
  tests/regtest_spec.py | grep -E $spec_regex > $spec_list

  write-test-cases

  cat $spec_list \
    | multi -- $0 _run-one-case || test-error $spec_regex

  log "Done running all test cases"

  make-summary $REGTEST_DIR
}

run-all() {
  # Limit it to this number of test cases.  By default we run all of them.
  local max_cases=${1:-1000000}
  local verbose=${2:-F} 

  mkdir --verbose -p $REGTEST_DIR
  # Print the spec
  #
  # -n3 has to match the number of arguments in the spec.

  #local func=_run-one-case-logged
  local func
  if test $verbose = T; then
    func=_run-one-case  # parallel process output mixed on the console
  else
    func=_run-one-case-logged  # one line
  fi

  log "Using $NUM_PROCS parallel processes"

  local spec_list=$REGTEST_DIR/spec-list.txt
  tests/regtest_spec.py > $spec_list

  write-test-cases

  head -n $max_cases $spec_list \
    | multi -P $NUM_PROCS -- $0 $func || test-error $spec_regex

  log "Done running all test cases"

  make-summary $REGTEST_DIR
}

"$@"
