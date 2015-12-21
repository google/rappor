#!/bin/bash
# 
# End-to-end tests for the dashboard.
#
# Usage:
#   ./regtest.sh <function name>
#
# NOTE: Must be run in this directory (rappor/pipeline).

set -o nounset
set -o pipefail
set -o errexit

# Create schema and params.
create-metadata() {
  mkdir -p _tmp/metadata
  echo 'Hello from regtest.sh'

  local params_path=_tmp/metadata/regtest_params.csv

  # Relying on $RAPPOR_SRC/regtest.sh
  cp --verbose ../_tmp/python/demo1/case_params.csv $params_path

  # For now, use the same map everywhere.
  cat >_tmp/metadata/dist-analysis.csv <<EOF
var,map_filename
unif,map.csv
gauss,map.csv
exp,map.csv
m.domain,domain_map.csv
EOF

  # Both single dimensional and multi dimensional metrics.
  cat >_tmp/metadata/rappor-vars.csv <<EOF 
metric,var,var_type,params
m,domain,string,m_params
m,flag..HTTPS,boolean,m_params
unif,,string,regtest_params
gauss,,string,regtest_params
exp,,string,regtest_params
EOF
}

# Create map files.
create-maps() {
  mkdir -p _tmp/maps
  # Use the same map for everyone now?
  local map_path=_tmp/maps/map.csv

  # Relying on $RAPPOR_SRC/regtest.sh
  cp --verbose ../_tmp/python/demo1/case_map.csv $map_path
}

# Simulate different metrics.
create-counts() {
  mkdir -p _tmp/counts

  for date in 2015-12-01 2015-12-02 2015-12-03; do
    mkdir -p _tmp/counts/$date

    # TODO: Change params for each day.
    cp --verbose \
      ../_tmp/python/demo1/1/case_counts.csv _tmp/counts/$date/unif_counts.csv
    cp --verbose \
      ../_tmp/python/demo2/1/case_counts.csv _tmp/counts/$date/gauss_counts.csv
    cp --verbose \
      ../_tmp/python/demo3/1/case_counts.csv _tmp/counts/$date/exp_counts.csv
  done
}

dist-task-spec() {
  local job_dir=$1
  ./task_spec.py dist \
    --map-dir _tmp/maps \
    --config-dir _tmp/metadata \
    --output-base-dir $job_dir/raw \
    --bad-report-out _tmp/bad_counts.csv \
    "$@"
}

dist-job() {
  local job_id=$1
  local pat=$2

  local job_dir=_tmp/$job_id
  mkdir -p $job_dir/raw

  local spec_list=$job_dir/spec-list.txt

  find _tmp/counts/$pat -name \*_counts.csv \
    | dist-task-spec $job_dir \
    | tee $spec_list

  ./dist.sh decode-dist-many $job_dir $spec_list
  ./dist.sh combine-and-render-html _tmp $job_dir
}

dist() {
  create-metadata
  create-maps
  create-counts

  dist-job smoke1 '2015-12-01'  # one day
  dist-job smoke2 '2015-12-0[23]'  # two days
}

# Simulate different metrics.
create-reports() {
  mkdir -p _tmp/reports

  for date in 2015-12-01 2015-12-02 2015-12-03; do
    mkdir -p _tmp/reports/$date

    # TODO: Change params for each day.
    cp --verbose \
      ../bin/_tmp/reports.csv _tmp/reports/$date/m_reports.csv
  done
}

assoc-task-spec() {
  local job_dir=$1
  ./task_spec.py assoc \
    --map-dir _tmp/maps \
    --config-dir _tmp/metadata \
    --output-base-dir $job_dir/raw \
    "$@"
}

assoc-job() {
  local job_id=$1
  local pat=$2

  local job_dir=_tmp/$job_id
  mkdir -p $job_dir/raw $job_dir/config

  local spec_list=$job_dir/spec-list.txt

  find _tmp/reports/$pat -name \*_reports.csv \
    | assoc-task-spec $job_dir \
    | tee $spec_list

  # decode-many calls decode_assoc.R, which expects this schema in the 'config'
  # dir now.  TODO: adjust this.
  cp --verbose _tmp/metadata/rappor-vars.csv $job_dir/config
  cp --verbose ../bin/_tmp/m_params.csv $job_dir/config

  ./assoc.sh decode-many $job_dir $spec_list
  ./assoc.sh combine-and-render-html _tmp $job_dir
}

# Copy some from bin/test.sh?  The input _reports.csv files should be taken
# from there.
assoc() {
  create-reports
  cp --verbose ../bin/_tmp/domain_map.csv _tmp/maps

  assoc-job smoke1-assoc '2015-12-01'  # one day
  assoc-job smoke2-assoc '2015-12-0[23]'  # two days
}

"$@"
