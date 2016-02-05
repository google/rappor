#!/bin/bash
#
# Run and end-to-end association test in parallel.
#
# Usage:
#   ./assoctest.sh <function name>

# At the end, it will print an HTML summary.
#
# Three main functions are
#    run [[<pattern> [<num> [<compare>]]] - run tests matching <pattern> in
#                               parallel, each <num> times, additionally
#                               running the EM algorithm if <compare> = T
#
#    run-seq [<pattern> [<num> [<compare>]]] - ditto, except that tests are run 
#                                              sequentially
#
#    run-all [<num> [<compare>]]             - run all tests, in parallel,
#                                              each <num> times
#
# Note: Patterns always start with a-.
#
# Examples:
# $ ./assoctest.sh run-seq a-toy      # Sequential run, matches 2 cases
# $ ./assoctest.sh run-seq a-fizz 3   # Sequential, each test is run three
#                                       times
# $ ./assoctest.sh run-all            # Run all tests once
# $ ./assoctest.sh run-all 5 T        # Run all tests five times with EM
#                                       comparisons
#
# The <pattern> argument is a regex in 'grep -E' format. (Detail: Don't
# use $ in the pattern, since it matches the whole spec line and not just the
# test case name.) The number of processors used in a parallel run is 5.
#
# fast_counts param inherited from regtest.sh, but currently not used

set -o nounset
set -o pipefail
set -o errexit

. util.sh

readonly THIS_DIR=$(dirname $0)
readonly REPO_ROOT=$THIS_DIR
readonly CLIENT_DIR=$REPO_ROOT/client/python
readonly ASSOCTEST_DIR=_tmp/assoctest

# All the Python tools need this
export PYTHONPATH=$CLIENT_DIR

# Print true inputs into a file with selected prefix
print-true-inputs() {
  local num_unique_values=$1
  local prefix=$2
  seq 1 $num_unique_values | awk '{print "'$prefix'" $1}'
}

# Generate a single test case, specified by a line of the test spec.
# This is a helper function for _run_tests().
_setup-one-case() {
  local test_case=$1

  # Input parameters
  local num_unique_values=$2
  local num_unique_values2=$3
  local num_clients=$4
  local num_extras=$5

  # RAPPOR params
  local num_bits=$6
  local num_hashes=$7
  local num_cohorts=$8
  local p=$9
  local q=${10}  # need curly braces to get the 10th arg
  local f=${11}

  banner 'Setting up parameters and candidate files for '$test_case

  local case_dir=$ASSOCTEST_DIR/$test_case
  mkdir --verbose -p $case_dir

  # Save the "spec"
  echo "$@" > $case_dir/spec.txt

  local params_path=$case_dir/case_params.csv

  echo 'k,h,m,p,q,f' > $params_path
  echo "$num_bits,$num_hashes,$num_cohorts,$p,$q,$f" >> $params_path

  print-true-inputs $[num_unique_values+num_extras] \
    "str" > $case_dir/case_true_inputs1.txt
  print-true-inputs $num_unique_values2 "opt" > $case_dir/case_true_inputs2.txt

  # Hash candidates
  analysis/tools/hash_candidates.py \
    $params_path \
    < $case_dir/case_true_inputs1.txt \
    > $case_dir/case_map1.csv

  analysis/tools/hash_candidates.py \
    $params_path \
    < $case_dir/case_true_inputs2.txt \
    > $case_dir/case_map2.csv
}

# Run a single test instance, specified by <test_name, instance_num>.
# This is a helper function for _run_tests().
_run-one-instance() {
  local test_case=$1
  local test_instance=$2

  local case_dir=$ASSOCTEST_DIR/$test_case

  read -r case_name num_unique_values num_unique_values2 \
    num_clients num_extras \
    num_bits num_hashes num_cohorts p q f compare < $case_dir/spec.txt

  local instance_dir=$ASSOCTEST_DIR/$test_case/$test_instance
  mkdir --verbose -p $instance_dir

  banner "Generating input"

  tests/gen_true_values_assoc.R $num_unique_values $num_unique_values2 \
                            $num_clients $num_cohorts $instance_dir/case.csv

  banner "Running RAPPOR client"
  tests/rappor_assoc_sim.py \
    --num-bits $num_bits \
    --num-hashes $num_hashes \
    --num-cohorts $num_cohorts \
    -p $p \
    -q $q \
    -f $f \
    < $instance_dir/case.csv \
    > "$instance_dir/case_reports.csv"

  analysis/tools/sum_bits_assoc.py \
    $case_dir/case_params.csv \
    "$instance_dir/case" \
    < $instance_dir/case_reports.csv


  local out_dir=${instance_dir}_report
  mkdir --verbose -p $out_dir

  # Currently, the summary file shows and aggregates timing of the inference
  # engine, which excludes R's loading time and reading of the (possibly
  # substantial) map file. Timing below is more inclusive.
  TIMEFORMAT='Running analyze.R took %R seconds'

  # Setting up JSON file
  json_file="{\
    \"maps\":           [\"$case_dir/case_map1.csv\",\
                       \"$case_dir/case_map2.csv\"],\
    \"reports\":        \"$instance_dir/case_reports.csv\",\
    \"truefile\":       \"$instance_dir/case.csv\",\
    \"outdir\":         \"$out_dir\",\
    \"params\":         \"$case_dir/case_params.csv\",\
    \"newalg\":         \"false\",\
    \"numvars\":        2,\
    \"num\":            $num_clients,\
    \"extras\":         $num_extras,\
    \"varcandidates\":  [$num_unique_values, $num_unique_values2],\
    \"verbose\":        \"true\",\
    \"counts\":         [\"$instance_dir/case_2way.csv\",\
                        \"$instance_dir/case_marg1.csv\",\
                        \"$instance_dir/case_marg2.csv\"],"

  # Adding EM comparison depending on $compare flag
  if test $compare = F; then
    json_file=$json_file"\"expt\": [\"external-counts\"]"
  else 
    json_file=$json_file"\"expt\": [\"external-counts\", \
      \"external-reports-em\"]"
  fi
  json_file=$json_file"}"
  echo $json_file > $instance_dir/analyze_inp.json
  
  time {
    tests/compare_assoc.R --inp $instance_dir/analyze_inp.json
  }
}

# Like _run-once-case, but log to a file.
_run-one-instance-logged() {
  local test_case_id=$1
  local test_case_run=$2

  local log_dir=$ASSOCTEST_DIR/$test_case_id/${test_case_run}_report
  mkdir --verbose -p $log_dir

  log "Started '$test_case_id' (instance $test_case_run) -- logging to $log_dir/log.txt"
  _run-one-instance "$@" >$log_dir/log.txt 2>&1 \
    && log "Test case $test_case_id (instance $test_case_run) done" \
    || log "Test case $test_case_id (instance $test_case_run) failed"
}

make-summary() {
  local dir=$1
  local filename=${2:-results.html}
  local instances=${3:-1}

  tests/make_summary_assoc.py $dir $instances > $dir/rows.html

  pushd $dir >/dev/null

  cat ../../tests/assoctest.html \
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
_setup-test-instances() {
  local instances=$1

  while read line; do
    for i in $(seq 1 $instances); do
      read case_name _ <<< $line  # extract the first token
      echo $case_name $i
    done
  done
}

# Args:
#   regexp: A pattern selecting the subset of tests to run
#   instances: A number of times each test case is run
#   parallel: Whether the tests are run in parallel (T/F)
#   fast_counts: Whether counts are sampled directly (T/F)
#   compare: Whether the tests run comparisons between EM and Marginal
#   algorithms or not
#
_run-tests() {
  local spec_regex=$1  # grep -E format on the spec
  local instances=$2
  local parallel=$3
  local fast_counts=$4
  local $compare=$5

  rm -r -f --verbose $ASSOCTEST_DIR

  mkdir --verbose -p $ASSOCTEST_DIR

  echo "PARAMS"
  echo $spec_regex
  echo $instances
  echo $parallel
  echo $fast_counts
  echo $compare

  local func
  local processors=1

  if test $parallel = F; then
    func=_run-one-instance-logged  # output to the console
  else
    func=_run-one-instance-logged
    processors=$(grep -c ^processor /proc/cpuinfo || echo 4)  # POSIX-specific
    if test $processors -gt 6; then  # leave few CPUs for the OS
      # Association tests take up a lot of memory; so restricted to a few
      # processes at a time
      processors=5
    else
      processors=1
    fi
    log "Running $processors parallel processes"
  fi

  local cases_list=$ASSOCTEST_DIR/test-cases.txt
  tests/assoctest_spec.py | grep -E $spec_regex | sed "s/$/ $compare/" > $cases_list

  # Generate parameters for all test cases.
  cat $cases_list \
    | xargs -l -P $processors -- $0 _setup-one-case \
    || test-error

  log "Done generating parameters for all test cases"

  local instances_list=$ASSOCTEST_DIR/test-instances.txt
  _setup-test-instances $instances $fast_counts < $cases_list > $instances_list

  cat $instances_list \
    | xargs -l -P $processors -- $0 $func || test-error

  log "Done running all test instances"

  make-summary $ASSOCTEST_DIR "results.html" $instances
}

# Run tests sequentially
run-seq() {
  local spec_regex=${1:-'^a-'}  # grep -E format on the spec
  local instances=${2:-1}
  local compare=${3:-F}

  _run-tests $spec_regex $instances F T $compare
}

# Run tests in parallel
run-all() {
  local instances=${1:-1}
  local compare=${2:-F}

  log "Running all tests. Can take a while."
  # a- for assoc tests
  # F for sequential
  _run-tests '^a-' $instances T T $compare
}

"$@"
