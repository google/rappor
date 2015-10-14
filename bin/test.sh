#!/bin/bash
#
# Simple smoke test for the decode-dist tool.  This will fail if your machine
# doesn't have the right R libraries.
#
# Usage:
#   ./test.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly RAPPOR_SRC=$(cd $THIS_DIR/.. && pwd)
readonly EM_EXECUTABLE=$RAPPOR_SRC/analysis/cpp/_tmp/fast_em

source $RAPPOR_SRC/util.sh


decode-dist-help() {
  time ./decode-dist --help
}

decode-dist() {
  # ./demo.sh quick-python creates these files
  local case_dir=../_tmp/python/demo3

  mkdir -p _tmp

  # Uses the ./demo.sh regtest files
  time ./decode-dist \
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
  time ./decode-assoc --help
}

write-assoc-testdata() {
  mkdir -p _tmp

  export PYTHONPATH=$RAPPOR_SRC/client/python

  cat >_tmp/true_values.csv <<EOF 
domain,flag..HTTPS
google.com,1
google.com,1
yahoo.com,1
yahoo.com,0
bing.com,1
bing.com,1
bing.com,0
EOF

  local num_bits=8
  local num_hashes=2
  local num_cohorts=128

  local prob_p=0.25
  local prob_q=0.75
  local prob_f=0.5

  # 7 items in the input.  7000 items is enough.
  local assoc_testdata_count=1000

  ../tests/rappor_sim.py \
    --assoc-testdata $assoc_testdata_count \
    --num-bits $num_bits \
    --num-hashes $num_hashes \
    --num-cohorts $num_cohorts \
    -p $prob_p \
    -q $prob_q \
    -f $prob_f \
    < _tmp/true_values.csv \
    > _tmp/reports.csv

  # Define a string variable and a boolean varaible.
  cat >_tmp/schema.csv <<EOF 
metric, var, var_type, params
m,domain,string,m_params
m,flag..HTTPS,boolean,m_params
EOF

  cat >_tmp/m_params.csv <<EOF
k,h,m,p,q,f
$num_bits,$num_hashes,$num_cohorts,$prob_p,$prob_q,$prob_f
EOF

  cat >_tmp/domain_candidates.csv <<EOF
google.com
yahoo.com
bing.com
EOF

  # Hash candidates to create map.
  ../analysis/tools/hash_candidates.py _tmp/m_params.csv \
    < _tmp/domain_candidates.csv \
    > _tmp/domain_map.csv
    
  banner "Wrote testdata in _tmp"
}

# Run the R version of association.
decode-assoc() {
  time ./decode-assoc \
    --metric-name m \
    --schema _tmp/schema.csv \
    --reports _tmp/reports.csv \
    --params-dir _tmp \
    --var1 domain \
    --var2 flag..HTTPS \
    --map1 _tmp/domain_map.csv \
    --max-em-iters 10 \
    --num-cores 2 \
    --output-dir _tmp \
    "$@"
}

build-em-executable() {
  pushd ../analysis/cpp >/dev/null
  ./run.sh build-fast-em
  popd >/dev/null
}

decode-assoc-cpp() {
  build-em-executable
  decode-assoc --em-executable "$EM_EXECUTABLE"
}

# TODO: Compare these results somehow?  Or just eyeball them.
decode-assoc-both() {
  write-assoc-testdata

  local log=_tmp/em-slow.log

  banner "Running slow association with R EM implementation"
  decode-assoc | tee $log
  banner "Wrote $log"

  local log=_tmp/em-fast.log

  banner "Running slow association with C++ EM implementation"
  decode-assoc-cpp | tee $log
  banner "Wrote $log"
}

# Run decode-assoc in a mode that only tests the EM step (i.e. it doesn't run the
# conditional step)
em-executable() {
  build-em-executable
  time ./decode-assoc \
    --test-em-executable \
    --em-executable $EM_EXECUTABLE
}

"$@"
