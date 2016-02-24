#!/bin/bash
usage() {
echo "
 Run end-to-end tests in parallel.

 Usage:
   ./regtest.sh <function name>
 At the end, it will print an HTML summary.
 
 Three main functions are 
    run [<pattern> [<lang>]] - run tests matching <pattern> in
                                       parallel. The language
                                       of the client to use.
    run-seq [<pattern> [<lang>]] - ditto, except that tests are run
                                       sequentially
    run-all                      - run all tests, in parallel

 Examples:
 $ ./regtest.sh run-seq unif-small-typical  # Run, the unif-small-typical test
 $ ./regtest.sh run-seq unif-small-         # Sequential, the tests containing:
                                            # 'unif-small-'
 $ ./regtest.sh run unif-  # Parallel run, matches multiple cases
 $ ./regtest.sh run-all    # Run all tests 

 The <pattern> argument is a regex in 'grep -E' format. (Detail: Don't
 use $ in the pattern, since it matches the whole spec line and not just the
 test case name.) The number of processors used in a parallel run is one less
 than the number of CPUs on the machine.
"
}
# Future speedups:
# - Reuse the same input -- come up with naming scheme based on params
# - Reuse the same maps -- ditto, rappor library can cache it
#

set -o nounset
set -o pipefail
set -o errexit

. util.sh

readonly THIS_DIR=$(dirname $0)
readonly REPO_ROOT=$THIS_DIR
readonly CLIENT_DIR=$REPO_ROOT/client/python
# subdirs are in _tmp/$impl, which shouldn't overlap with anything else in _tmp
readonly REGTEST_BASE_DIR=_tmp

# All the Python tools need this
export PYTHONPATH=$CLIENT_DIR

print-unique-values() {
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
#   unique_values: File of unique true values
#   last_true: last true input, e.g. 50 if we generated "v1" .. "v50".
#   num_additional: additional candidates to generate (starting at 'last_true')
#   to_remove: Regex of true values to omit from the candidates list, or the
#     string 'NONE' if none should be.  (Our values look like 'v1', 'v2', etc. so
#     there isn't any ambiguity.)
print-candidates() {
  local unique_values=$1
  local last_true=$2
  local num_additional=$3 
  local to_remove=$4

  if test $to_remove = NONE; then
    cat $unique_values  # include all true inputs
  else
    egrep -v $to_remove $unique_values  # remove some true inputs
  fi
  more-candidates $last_true $num_additional
}

# Generate a single test case, specified by a line of the test spec.
# This is a helper function for _run_tests().
_setup-one-case() {
  local impl=$1
  shift  # impl is not part of the spec; the next 13 params are

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

  local case_dir=$REGTEST_BASE_DIR/$impl/$test_case
  mkdir --verbose -p $case_dir

  # Save the "spec"
  echo "$@" > $case_dir/spec.txt

  local params_path=$case_dir/case_params.csv

  echo 'k,h,m,p,q,f' > $params_path
  echo "$num_bits,$num_hashes,$num_cohorts,$p,$q,$f" >> $params_path

  print-unique-values $num_unique_values > $case_dir/case_unique_values.txt

  local true_map_path=$case_dir/case_true_map.csv

  bin/hash_candidates.py \
    $params_path \
    < $case_dir/case_unique_values.txt \
    > $true_map_path

  # banner "Constructing candidates"

  print-candidates \
    $case_dir/case_unique_values.txt $num_unique_values \
    $num_additional "$to_remove" \
    > $case_dir/case_candidates.txt

  # banner "Hashing candidates to get 'map'"

  bin/hash_candidates.py \
    $params_path \
    < $case_dir/case_candidates.txt \
    > $case_dir/case_map.csv
}

# Run a single test instance, specified by <test_name, instance_num>.
# This is a helper function for _run_tests().
_run-one-instance() {
  local test_case=$1
  local test_instance=$2
  local impl=$3

  local case_dir=$REGTEST_BASE_DIR/$impl/$test_case
  
  read -r \
    case_name distr num_unique_values num_clients values_per_client \
    num_bits num_hashes num_cohorts p q f \
    num_additional to_remove \
    < $case_dir/spec.txt

  local instance_dir=$case_dir/$test_instance
  mkdir --verbose -p $instance_dir

  banner "Generating reports (gen_reports.R)"

  # the TRUE_VALUES_PATH environment variable can be used to avoid
  # generating new values every time.  NOTE: You are responsible for making
  # sure the params match!

  local true_values=${TRUE_VALUES_PATH:-}
  if test -z "$true_values"; then
    true_values=$instance_dir/case_true_values.csv
    tests/gen_true_values.R $distr $num_unique_values $num_clients \
                            $values_per_client $num_cohorts \
                            $true_values
  else
    # TEMP hack: Make it visible to plot.
    # TODO: Fix compare_dist.R
    ln -s -f --verbose \
      $PWD/$true_values \
      $instance_dir/case_true_values.csv
  fi

  case $impl in
    python)
      banner "Running RAPPOR Python client"

      # Writes encoded "out" file, true histogram, true inputs to
      # $instance_dir.
      time tests/rappor_sim.py \
        --num-bits $num_bits \
        --num-hashes $num_hashes \
        --num-cohorts $num_cohorts \
        -p $p \
        -q $q \
        -f $f \
        < $true_values \
        > "$instance_dir/case_reports.csv"
      ;;
      
    cpp)
      banner "Running RAPPOR C++ client (see rappor_sim.log for errors)"

      time client/cpp/_tmp/rappor_sim \
        $num_bits \
        $num_hashes \
        $num_cohorts \
        $p \
        $q \
        $f \
        < $true_values \
        > "$instance_dir/case_reports.csv" \
        2>"$instance_dir/rappor_sim.log"
      ;;
      
    *)
      log "Invalid impl $impl (should be one of python|cpp)"
      exit 1
    ;;
    
  esac

  banner "Summing RAPPOR IRR bits to get 'counts'"

  bin/sum_bits.py \
    $case_dir/case_params.csv \
    < $instance_dir/case_reports.csv \
    > $instance_dir/case_counts.csv

  local out_dir=${instance_dir}_report
  mkdir --verbose -p $out_dir

  # Currently, the summary file shows and aggregates timing of the inference
  # engine, which excludes R's loading time and reading of the (possibly 
  # substantial) map file. Timing below is more inclusive.
  TIMEFORMAT='Running compare_dist.R took %R seconds'
  time {
    # Input prefix, output dir
    tests/compare_dist.R -t "Test case: $test_case (instance $test_instance)" \
                         "$case_dir/case" "$instance_dir/case" $out_dir
  }
}

# Like _run-once-case, but log to a file.
_run-one-instance-logged() {
  local test_case=$1
  local test_instance=$2
  local impl=$3

  local log_dir=$REGTEST_BASE_DIR/$impl/$test_case/${test_instance}_report
  mkdir --verbose -p $log_dir

  log "Started '$test_case' (instance $test_instance) -- logging to $log_dir/log.txt"
  _run-one-instance "$@" >$log_dir/log.txt 2>&1 \
    && log "Test case $test_case (instance $test_instance) done" \
    || log "Test case $test_case (instance $test_instance) failed"
}

make-summary() {
  local dir=$1
  local impl=$2

  local filename=results.html

  tests/make_summary.py $dir $dir/rows.html

  pushd $dir >/dev/null

  cat ../../tests/regtest.html \
    | sed -e '/__TABLE_ROWS__/ r rows.html' -e "s/_IMPL_/$impl/g" \
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
# Third column is impl.
_setup-test-instances() {
  local instances=$1
  local impl=$2

  while read line; do
    for i in $(seq 1 $instances); do
      read case_name _ <<< $line  # extract the first token
      echo $case_name $i $impl
    done
  done
}

# Print the default number of parallel processes, which is max(#CPUs - 1, 1)
default-processes() {
  processors=$(grep -c ^processor /proc/cpuinfo || echo 4)  # Linux-specific
  if test $processors -gt 1; then  # leave one CPU for the OS
    processors=$(expr $processors - 1)
  fi
  echo $processors
}

# Args:
#   spec_gen: A program to execute to generate the spec.
#   spec_regex: A pattern selecting the subset of tests to run
#   parallel: Whether the tests are run in parallel (T/F).  Sequential
#     runs log to the console; parallel runs log to files.
#   impl: one of python, or cpp
#   instances: A number of times each test case is run

_run-tests() {
  local spec_gen=$1
  local spec_regex="$2"  # grep -E format on the spec, can be empty
  local parallel=$3
  local impl=${4:-"cpp"}
  local instances=${5:-1}

  local regtest_dir=$REGTEST_BASE_DIR/$impl
  rm -r -f --verbose $regtest_dir
  
  mkdir --verbose -p $regtest_dir

  local func
  local processors

  if test $parallel = F; then
    func=_run-one-instance  # output to the console
    processors=1
  else
    func=_run-one-instance-logged
    # Let the user override with MAX_PROC, in case they don't have enough
    # memory.
    processors=${MAX_PROC:-$(default-processes)}
    log "Running $processors parallel processes"
  fi

  local cases_list=$regtest_dir/test-cases.txt
  # Need -- for regexes that start with -
  $spec_gen | grep -E -- "$spec_regex" > $cases_list

  # Generate parameters for all test cases.
  cat $cases_list \
    | xargs -l -P $processors -- $0 _setup-one-case $impl \
    || test-error

  log "Done generating parameters for all test cases"

  local instances_list=$regtest_dir/test-instances.txt
  _setup-test-instances $instances $impl < $cases_list > $instances_list 

  cat $instances_list \
    | xargs -l -P $processors -- $0 $func || test-error

  log "Done running all test instances"

  make-summary $regtest_dir $impl
}

# used for most tests
readonly REGTEST_SPEC=tests/regtest_spec.py

# Run tests sequentially.  NOTE: called by demo.sh.
run-seq() {
  local spec_regex=${1:-'^r-'}  # grep -E format on the spec
  shift

  time _run-tests $REGTEST_SPEC $spec_regex F $@
}

# Run tests in parallel
run() {
  local spec_regex=${1:-'^r-'}  # grep -E format on the spec
  shift
  
  time _run-tests $REGTEST_SPEC $spec_regex T $@
}

# Run tests in parallel (7+ minutes on 8 cores)
run-all() {
  log "Running all tests. Can take a while."
  time _run-tests $REGTEST_SPEC '^r-' T cpp
}

run-user() {
  local spec_regex=${1:-}
  local parallel=T  # too much memory
  time _run-tests tests/user_spec.py "$spec_regex" $parallel cpp
}

# Use stable true values
compare-python-cpp() {
  local num_unique_values=100
  local num_clients=10000
  local values_per_client=10
  local num_cohorts=64

  local true_values=$REGTEST_BASE_DIR/stable_true_values.csv

  tests/gen_true_values.R \
    exp $num_unique_values $num_clients $values_per_client $num_cohorts \
    $true_values

  wc -l $true_values

  # Run Python and C++ simulation on the same input

  ./build.sh cpp-client

  TRUE_VALUES_PATH=$true_values \
    ./regtest.sh run-seq '^demo3' 1 python

  TRUE_VALUES_PATH=$true_values \
    ./regtest.sh run-seq '^demo3' 1 cpp

  head _tmp/{python,cpp}/demo3/1/case_reports.csv
}

if test $# -eq 0 ; then
  usage
else
  "$@"
fi
