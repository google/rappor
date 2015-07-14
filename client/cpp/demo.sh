#!/bin/bash
#
# Usage:
#   ./demo.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

readonly RAPPOR_SRC=$(cd ../.. && pwd)

readonly DIST=exp_cpp

readonly num_bits=8
readonly num_hashes=2
readonly num_cohorts=128
readonly p=0.25
readonly q=0.75
readonly f=0.5

# Params from rappor_test
gen-params() {
  cat >$RAPPOR_SRC/_tmp/${DIST}_params.csv <<EOF
k,h,m,p,q,f
$num_bits,$num_hashes,$num_cohorts,$p,$q,$f
EOF
}

# Generate files in line mode

# We will have 64 cohorts
gen-reports() {
  pushd $RAPPOR_SRC

  #../../tests/gen_sim_input.py -h
  local num_unique_values=100
  local num_clients=100000
  local values_per_client=10
  tests/gen_reports.R exp $num_unique_values $num_clients $values_per_client \
    _tmp/exp_cpp_reports.csv
  popd
}

print-true-inputs() {
  pushd $RAPPOR_SRC
  ./regtest.sh print-true-inputs 100 > _tmp/exp_cpp_true_inputs.txt
  popd
}

# Print candidates from true inpputs
make-candidates() {
  local dist=exp_cpp
  cp \
    $RAPPOR_SRC/_tmp/${dist}_true_inputs.txt \
    $RAPPOR_SRC/_tmp/${dist}_candidates.txt
}

make-map() {
  local dist=$DIST

  pushd $RAPPOR_SRC
  export PYTHONPATH=$RAPPOR_SRC/client/python

  analysis/tools/hash_candidates.py \
    _tmp/${dist}_params.csv \
    < _tmp/${dist}_candidates.txt \
    > _tmp/${dist}_map.csv
  popd
}

rappor-sim() {
  make _tmp/rappor_test
  pushd $RAPPOR_SRC

  local out=_tmp/exp_cpp_out.csv
  #time head -n 30 _tmp/exp_cpp_reports.csv \
  time cat _tmp/exp_cpp_reports.csv \
    | client/proto/_tmp/rappor_test \
      $num_bits $num_hashes $num_cohorts \
    > $out \
    2>_tmp/rappor_test.log
  head -n 30 $out

  grep -A1 MD5 _tmp/rappor_test.log  | sort | uniq -c
 
  popd
}

rappor-sim-golden() {
  pushd $RAPPOR_SRC
  export PYTHONPATH=$RAPPOR_SRC/client/python

  local out=_tmp/rappor-sim-golden
  mkdir -p $out

  tests/rappor_sim.py \
    --num-bits 8 \
    --num-hashes 2 \
    --num-cohorts 128 \
    -p 0.25 \
    -q 0.75 \
    -f 0.5 \
    -i _tmp/exp_cpp_reports.csv \
    --out-prefix $out/exp_cpp \
    2>_tmp/rappor_sim.log

  ls -al $out
  head -n 30 $out/exp_cpp_out.csv

  grep MD5 _tmp/rappor_sim.log | head -n 30
  popd
}

sum-bits() {
  pushd $RAPPOR_SRC
  export PYTHONPATH=$RAPPOR_SRC/client/python
  analysis/tools/sum_bits.py \
    _tmp/${DIST}_params.csv \
    < _tmp/${DIST}_out.csv \
    > _tmp/${DIST}_counts.csv
  popd
}

# This part is like rappor_sim.py, but in C++.
# We take a "client,string" CSV (no header) and want a 'client,cohort,rappor'
# exp_cpp_out.csv file
#
# TODO: rappor_test.cc can generate a new client every time I guess.

encode-cohort() {
  make _tmp/rappor_test
  pushd $RAPPOR_SRC

  local cohort=$1

  # Disregard logs on stderr
  # Client is stubbed out

  time cat _tmp/exp_cpp_reports.csv \
    | client/proto/_tmp/rappor_test $cohort 2>/dev/null #\
    > _tmp/cohort_$cohort.csv
    #| awk -v cohort=$cohort -v client=0 '{print client "," cohort "," $1 }' \
}

encode-demo() {
  make _tmp/rappor_test
  pushd $RAPPOR_SRC
  local out=_tmp/encode_demo.txt
  local num_cohorts=4  # matches params
  time head -n 100 _tmp/exp_cpp_reports.csv \
    | client/proto/_tmp/rappor_test $num_cohorts > $out
  echo
  echo OUTPUT
  cat $out
}

test-rappor-test() {
  set -x
  make _tmp/rappor_test 
  #_tmp/rappor_test bad
  _tmp/rappor_test 3
}

readonly NUM_COHORTS=64

histogram() {
  python -c '
import collections
import csv
import sys

counter = collections.Counter()
with open(sys.argv[1]) as in_file:
  for line in in_file:
    line = line.strip()
    try:
      value = line.split(",")[1]  # second row
    except IndexError:
      print value
      raise
    counter[value] += 1

with open(sys.argv[2], "w") as out_file:
  c = csv.writer(out_file)
  c.writerow(("string", "count"))
  for value, count in counter.iteritems():
    c.writerow((value, str(count)))
' $RAPPOR_SRC/_tmp/${DIST}_reports.csv $RAPPOR_SRC/_tmp/${DIST}_hist.csv
}

compare-dist() {
  pushd $RAPPOR_SRC
  local dist=exp_cpp  # fake one

  local case_dir=_tmp
  local instance_dir=_tmp/1
  local out_dir=${instance_dir}_report

  # Temporary hack until analyze.R has better syntax.
  mkdir -p $instance_dir
  cp --verbose _tmp/${DIST}_counts.csv $instance_dir
  cp --verbose _tmp/${DIST}_hist.csv $instance_dir

  mkdir --verbose -p $out_dir

  echo "Analyzing RAPPOR output ($dist)"
  tests/analyze.R -t "exp cpp" \
    $case_dir/$dist \
    $instance_dir/$dist \
    $out_dir
  popd
}

cpp() {
  gen-params
  gen-reports
  print-true-inputs
  make-candidates
  make-map
  rappor-sim
  sum-bits
  histogram
  compare-dist

  # Has to come AFTER, so it uses the same reports
  rappor-sim-golden
}

"$@"
