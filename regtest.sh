#!/bin/bash
#
# Run end-to-end tests in parallel.
#
# Usage:
#   ./regtest.sh <function name>

# At the end, it will print an HTML summary.
# 
# Three main functions are 
#    run [[<pattern> [<num> [<fast>]] - run tests matching <pattern> in
#                                       parallel, each <num> times. The fast 
#                                       mode (T/F) shortcuts generation of 
#                                       reports.
#    run-seq [<pattern> [<num> [<fast>]] - ditto, except that tests are run
#                                       sequentially
#    run-all [<num>]              - run all tests, in parallel, each <num> times
#
# Examples:
# $ ./regtest.sh run-seq unif-small-typical  # Sequential run, matches 1 case
# $ ./regtest.sh run-seq unif-small- 3 F  # Sequential, each test is run three
#                                           times, using slow generation
# $ ./regtest.sh run unif-  # Parallel run, matches multiple cases
# $ ./regtest.sh run unif- 5 # Parallel run, matches multiple cases, each test 
#                              is run 5 times
# $ ./regtest.sh run-all     # Run all tests once
#
# The <pattern> argument is a regex in 'grep -E' format. (Detail: Don't
# use $ in the pattern, since it matches the whole spec line and not just the
# test case name.) The number of processors used in a parallel run is one less
# than the number of CPUs on the machine.


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

# Generate a single test case, specified by a line of the test spec.
# This is a helper function for _run_tests().
_setup-one-case() {
  local test_case=$1

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
  local q=${10}  # need curly braces to get the 10th arg
  local f=${11}

  # map params
  local num_additional=${12}
  local to_remove=${13}

  banner 'Setting up parameters and candidate files for '$test_case

  local case_dir=$REGTEST_DIR/$test_case
  mkdir --verbose -p $case_dir

  # Save the "spec"
  echo "$@" > $case_dir/spec.txt

  local params_path=$case_dir/case_params.csv

  echo 'k,h,m,p,q,f' > $params_path
  echo "$num_bits,$num_hashes,$num_cohorts,$p,$q,$f" >> $params_path

  print-true-inputs $num_unique_values > $case_dir/case_true_inputs.txt

  local true_map_path=$case_dir/case_true_map.csv

  analysis/tools/hash_candidates.py \
    $params_path \
    < $case_dir/case_true_inputs.txt \
    > $true_map_path

  # banner "Constructing candidates"

  print-candidates \
    $case_dir/case_true_inputs.txt $num_unique_values \
    $num_additional "$to_remove" \
    > $case_dir/case_candidates.txt

  # banner "Hashing candidates to get 'map'"

  analysis/tools/hash_candidates.py \
    $case_dir/case_params.csv \
    < $case_dir/case_candidates.txt \
    > $case_dir/case_map.csv
}

# Run a single test instance, specified by <test_name, instance_num>.
# This is a helper function for _run_tests().
_run-one-instance() {
  local test_case=$1
  local test_instance=$2
  local fast_counts=$3

  local case_dir=$REGTEST_DIR/$test_case
  
  read -r case_name distr num_unique_values num_clients \
    values_per_client num_bits num_hashes num_cohorts p q f num_additional \
    to_remove < $case_dir/spec.txt

  local instance_dir=$REGTEST_DIR/$test_case/$test_instance
  mkdir --verbose -p $instance_dir

  if test $fast_counts = T; then
    local params_file=$case_dir/case_params.csv
    local true_map_file=$case_dir/case_true_map.csv

    banner "Using gen_counts.R"

    tests/gen_counts.R $distr $num_clients $values_per_client $params_file \
                       $true_map_file "$instance_dir/case"
  else
    banner "Generating input"

    tests/gen_reports.R $distr $num_unique_values $num_clients \
                        $values_per_client $instance_dir/case.csv

    banner "Running RAPPOR client"

    # Writes encoded "out" file, true histogram, true inputs to $instance_dir.
    tests/rappor_sim.py \
      --num-bits $num_bits \
      --num-hashes $num_hashes \
      --num-cohorts $num_cohorts \
      -p $p \
      -q $q \
      -f $f \
      -i $instance_dir/case.csv \
      --out-prefix "$instance_dir/case"

    banner "Summing bits to get 'counts'"

    analysis/tools/sum_bits.py \
      $case_dir/case_params.csv \
      < $instance_dir/case_out.csv \
      > $instance_dir/case_counts.csv
  fi

  local out_dir=${instance_dir}_report
  mkdir --verbose -p $out_dir

  # Currently, the summary file shows and aggregates timing of the inference
  # engine, which excludes R's loading time and reading of the (possibly 
  # substantial) map file. Timing below is more inclusive.
  TIMEFORMAT='Running analyze.R took %R seconds'
  time {
    # Input prefix, output dir
    tests/analyze.R -t "Test case: $test_case (instance $test_instance)" \
                       "$case_dir/case" "$instance_dir/case" $out_dir
  }
}

# Like _run-once-case, but log to a file.
_run-one-instance-logged() {
  local test_case_id=$1
  local test_case_run=$2

  local log_dir=$REGTEST_DIR/$test_case_id/${test_case_run}_report
  mkdir --verbose -p $log_dir

  log "Started '$test_case_id' (instance $test_case_run) -- logging to $log_dir/log.txt"
  _run-one-instance "$@" >$log_dir/log.txt 2>&1 \
    && log "Test case $test_case_id (instance $test_case_run) done" \
    || log "Test case $test_case_id (instance $test_case_run) failed"
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

test-error() {
  local spec_regex=${1:-}
  log "Some test cases failed"
  if test -n "$spec_regex"; then
    log "(Perhaps none matched pattern '$spec_regex')"
  fi
  # don't quit just yet
  # exit 1 
}

# Assuming the spec file, write a list of test case names (first column) with
# the instance ids (second column), where instance ids run from 1 to $1.
# Third column is fast_counts (T/F).
_setup-test-instances() {
  local instances=$1
  local fast_counts=$2

  while read line; do
    for i in $(seq 1 $instances); do
      read case_name _ <<< $line  # extract the first token
      echo $case_name $i $fast_counts
    done
  done
}

# Args:
#   regexp: A pattern selecting the subset of tests to run
#   instances: A number of times each test case is run
#   parallel: Whether the tests are run in parallel (T/F)
#   fast_counts: Whether counts are sampled directly (T/F)
#   
_run-tests() {
  local spec_regex=$1  # grep -E format on the spec
  local instances=$2
  local parallel=$3
  local fast_counts=$4

  rm -r -f --verbose $REGTEST_DIR
  
  mkdir --verbose -p $REGTEST_DIR

  local func
  local processors=1

  if test $parallel = F; then
    func=_run-one-instance  # output to the console
  else
    func=_run-one-instance-logged
    processors=$(grep -c ^processor /proc/cpuinfo || echo 4)  # POSIX-specific
    if test $processors -gt 1; then  # leave one CPU for the OS
      processors=$(expr $processors - 1)
    fi
    log "Running $processors parallel processes"
  fi

  local cases_list=$REGTEST_DIR/test-cases.txt
  tests/regtest_spec.py | grep -E $spec_regex > $cases_list

  # Generate parameters for all test cases.
  cat $cases_list \
    | xargs -l -P $processors -- $0 _setup-one-case \
    || test-error

  log "Done generating parameters for all test cases"

  local instances_list=$REGTEST_DIR/test-instances.txt
  _setup-test-instances $instances $fast_counts < $cases_list > $instances_list 

  cat $instances_list \
    | xargs -l -P $processors -- $0 $func || test-error

  log "Done running all test instances"

  make-summary $REGTEST_DIR
}

# Run tests sequentially
run-seq() {
  local spec_regex=${1:-'^r-'}  # grep -E format on the spec
  local instances=${2:-1}
  local fast_counts=${3:-T}

  _run-tests $spec_regex $instances F $fast_counts
}

# Run tests in parallel
run() {
  local spec_regex=${1:-'^r-'}  # grep -E format on the spec
  local instances=${2:-1}
  local fast_counts=${3:-T}
  
  _run-tests $spec_regex $instances T $fast_counts 
}

# Run tests in parallel
run-all() {
  local instances=${1:-1}

  log "Running all tests. Can take a while."
  _run-tests '^r-' $instances T T
}

"$@"
