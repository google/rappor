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

readonly NUM_SPEC_COLS=13

# TODO: Get num cpus
readonly NUM_PROCS=${NUM_PROCS:-12}

print-true-inputs() {
  local num_unique_values=$1
  seq 1 $num_unique_values | awk '{print "v" $1}'
}

# Add some more candidates here.  We hope these are estimated at 0.
# e.g. if add_start=51, and num_additional is 20, show v51-v70
more-candidates() {
  local last_true=$1
  local num_additional=$2

  local begin
  local end
  begin=$(expr $last_true + 1)
  end=$(expr $last_true + $num_additional)

  seq $begin $end | awk '{print "v" $1}'
}

# Args:
#   true_inputs: File of true inputs
#   last_true: last true input, e.g. 50 if we generated "v1" .. "v50".
#   num_additional: additional candidates to generate (starting at 'last_true')
#   to_remove: Regex of true values to omit from the candidates list, or the
#     string 'NONE' if none should be.  (Our values look like 'v1', 'v2', etc. so
#     there isn't any ambiguity.)
print-candidates() {
  local true_inputs=$1
  local last_true=$2
  local num_additional=$3 
  local to_remove=$4

  if test $to_remove = NONE; then
    cat $true_inputs  # include all true inputs
  else
    egrep -v $to_remove $true_inputs  # remove some true inputs
  fi
  more-candidates $last_true $num_additional
}

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

  # Save the "spec" for showing in the summary.
  echo "$@" > $case_dir/spec.txt

  local fast_counts=F
  # local fast_counts=T

  if test $fast_counts = T; then
    # Print params CSV.  No JSON.
    local params_path=$case_dir/case_params.csv
    echo 'k,h,m,p,q,f' > $params_path
    echo "$num_bits,$num_hashes,$num_cohorts,$p,$q,$f" >> $params_path

    print-true-inputs $num_unique_values > $case_dir/case_true_inputs.txt

    local true_map_path=$case_dir/case_true_map.csv
    analysis/tools/hash_candidates.py \
      $params_path \
      < $case_dir/case_true_inputs.txt \
      > $true_map_path

    local num_reports=$(expr $num_clients \* $values_per_client)

    banner "Using gen_counts.R"
    tests/gen_counts.R $params_path $true_map_path $dist $num_reports \
                       "$case_dir/case"
  else

    banner "Generating input"

    tests/gen_sim_input.py \
      -d $dist \
      -c $num_clients \
      -u $num_unique_values \
      -v $values_per_client \
      > $case_dir/case.csv

    banner "Running RAPPOR client"

    # Writes encoded "out" file, true histogram, true inputs, params CSV and JSON
    # to $case_dir.
    tests/rappor_sim.py \
      --num-bits $num_bits \
      --num-hashes $num_hashes \
      --num-cohorts $num_cohorts \
      -p $p \
      -q $q \
      -f $f \
      -i $case_dir/case.csv \
      --out-prefix "$case_dir/case"

    banner "Summing bits to get 'counts'"

    analysis/tools/sum_bits.py \
      $case_dir/case_params.csv \
      < $case_dir/case_out.csv \
      > $case_dir/case_counts.csv
  fi

  banner "Constructing candidates"

  # Reuse demo.sh function
  print-candidates \
    $case_dir/case_true_inputs.txt $num_unique_values \
    $num_additional "$to_remove" \
    > $case_dir/case_candidates.txt

  banner "Hashing candidates to get 'map'"

  analysis/tools/hash_candidates.py \
    $case_dir/case_params.csv \
    < $case_dir/case_candidates.txt \
    > $case_dir/case_map.csv

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
  local filename=${2:-results.html}

  tests/make_summary.py $dir > $dir/rows.html

  pushd $dir >/dev/null

  cat ../../tests/regtest.html \
    | sed -e '/TABLE_ROWS/ r rows.html' \
    > $filename

  popd >/dev/null

  log "Wrote $dir/$filename"
  log "URL: file://$PWD/$dir/$filename"
}

# Helper to parse spec input with xargs
multi() {
  xargs -n $NUM_SPEC_COLS --no-run-if-empty --verbose "$@"
}

test-error() {
  local spec_regex=${1:-}
  log "Some test cases failed"
  if test -n "$spec_regex"; then
    log "(Perhaps none matched pattern '$spec_regex')"
  fi
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
  local html_filename=${2:-results.html}  # demo.sh changes it to demo.sh

  mkdir --verbose -p $REGTEST_DIR

  local spec_list=$REGTEST_DIR/spec-list.txt
  tests/regtest_spec.py | grep -E $spec_regex > $spec_list

  write-test-cases

  cat $spec_list \
    | multi -- $0 _run-one-case || test-error $spec_regex

  log "Done running all test cases"

  make-summary $REGTEST_DIR $html_filename
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
    | multi -P $NUM_PROCS -- $0 $func || test-error

  log "Done running all test cases"

  make-summary $REGTEST_DIR
}

"$@"
