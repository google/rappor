#!/bin/bash
#
# Run and end-to-end association test in parallel.
#
# Usage:
#   ./assoctest.sh <function name>

# At the end, it will print an HTML summary.
#
# Three main functions are
#    run [[<pattern> [<num>]] - run tests matching <pattern> in
#                               parallel, each <num> times.
#
#    ## run-seq currently not supported!
#    run-seq [<pattern> [<num>]] - ditto, except that tests are run sequentially
#    ## --
#
#    run-all [<num>]             - run all tests, in parallel, each <num> times
#
# Examples:
# $ ./regtest.sh run-seq tiny-8x16-  # Sequential run, matches 2 cases
# $ ./regtest.sh run-seq tiny-8x16- 3  # Sequential, each test is run three
#                                           times
# $ ./regtest.sh run-all     # Run all tests once
#
# The <pattern> argument is a regex in 'grep -E' format. (Detail: Don't
# use $ in the pattern, since it matches the whole spec line and not just the
# test case name.) The number of processors used in a parallel run is one less
# than the number of CPUs on the machine.


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
    num_bits num_hashes num_cohorts p q f < $case_dir/spec.txt

  local instance_dir=$ASSOCTEST_DIR/$test_case/$test_instance
  mkdir --verbose -p $instance_dir

  banner "Generating input"

  tests/gen_assoc_reports.R $num_unique_values $num_unique_values2 \
                            $num_clients $instance_dir/case.csv

  banner "Running RAPPOR client"
  tests/rappor_assoc_sim.py \
    --num-bits $num_bits \
    --num-hashes $num_hashes \
    --num-cohorts $num_cohorts \
    -p $p \
    -q $q \
    -f $f \
    -i $instance_dir/case.csv \
    --out-prefix "$instance_dir/case"

  analysis/tools/sum_bits_assoc.py \
    $case_dir/case_params.csv \
    "$instance_dir/case" \
    < $instance_dir/case_out.csv


  # Setting up JSON file containing assoc_sim inputs with python
  python -c "import json; \
    f = file('$instance_dir/assoc_inp.json', 'w'); \
    inp = dict(); \
    inp['params'] = '$case_dir/case_params.csv'; \
    inp['reports'] = '$instance_dir/reports.csv'; \
    inp['true'] = '$instance_dir/truedist.csv'; \
    inp['map'] = '$instance_dir/map'; \
    inp['num'] = $num_clients; \
    inp['extras'] = 0; \
    inp['distr'] = 'zipf2'; \
    inp['prefix'] = './'; \
    inp['vars'] = 2; \
    inp['varcandidates'] = [$num_unique_values, $num_unique_values2]; \
    json.dump(inp, f); \
    f.close();"

  # tests/assoc_sim_expt.R --inp $instance_dir/assoc_inp.json

  local out_dir=${instance_dir}_report
  mkdir --verbose -p $out_dir

  # Currently, the summary file shows and aggregates timing of the inference
  # engine, which excludes R's loading time and reading of the (possibly
  # substantial) map file. Timing below is more inclusive.
  TIMEFORMAT='Running analyze.R took %R seconds'

  # Setting up JSON file with python
  python -c "import json; \
    f = file('$instance_dir/analyze_inp.json', 'w'); \
    inp = dict(); \
    inp['maps'] = ['$case_dir/case_map1.csv',\
                   '$case_dir/case_map2.csv']; \
    inp['reports'] = '$instance_dir/reports.csv'; \
    inp['truefile'] = '$instance_dir/case.csv'; \
    inp['outdir'] = '$out_dir'; \
    inp['params'] = '$case_dir/case_params.csv'; \
    inp['newalg'] = 'false'; \
    inp['numvars'] = 2; \
    inp['num'] = $num_clients; \
    inp['extras'] = $num_extras; \
    inp['varcandidates'] = [$num_unique_values, $num_unique_values2]; \
    inp['counts'] = ['$instance_dir/case_2way.csv',\
                     '$instance_dir/case_marg1.csv',\
                     '$instance_dir/case_marg2.csv']; \
    inp['expt'] = 'external-counts'; \
    json.dump(inp, f); \
    f.close();"

  time {
    tests/analyze_assoc_expt.R --inp $instance_dir/analyze_inp.json
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

  tests/make_summary_assoc.py $dir > $dir/rows.html

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
#
_run-tests() {
  local spec_regex=$1  # grep -E format on the spec
  local instances=$2
  local parallel=$3
  local fast_counts=$4

  rm -r -f --verbose $ASSOCTEST_DIR

  mkdir --verbose -p $ASSOCTEST_DIR

  echo "PARAMS"
  echo $spec_regex
  echo $instances
  echo $parallel
  echo $fast_counts

  local func
  local processors=1

  if test $parallel = F; then
    func=_run-one-instance-logged  # output to the console
  else
    func=_run-one-instance-logged
    processors=$(grep -c ^processor /proc/cpuinfo || echo 4)  # POSIX-specific
    if test $processors -gt 1; then  # leave one CPU for the OS
      processors=$(expr $processors - 1)
    fi
    log "Running $processors parallel processes"
  fi

  local cases_list=$ASSOCTEST_DIR/test-cases.txt
  tests/regtest_spec.py | grep -E $spec_regex > $cases_list

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

  make-summary $ASSOCTEST_DIR
}

# Run tests sequentially
#run-seq() {
#  local spec_regex=${1:-'^r-'}  # grep -E format on the spec
#  local instances=${2:-1}
#  local fast_counts=${3:-T}
#
#  _run-tests $spec_regex $instances F $fast_counts
#}

# Run tests in parallel
#run() {
#  local spec_regex=${1:-'^r-'}  # grep -E format on the spec
#  local instances=${2:-1}
#  local fast_counts=${3:-T}
#
#  _run-tests $spec_regex $instances T $fast_counts
#}

# Run tests in parallel
run-all() {
  local instances=${1:-1}

  log "Running all tests. Can take a while."
  # a- for assoc tests
  # F for sequential
  _run-tests '^a-' $instances F T
}

"$@"
