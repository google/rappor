#!/bin/bash
#
# Take the raw data from the analysis and massage it into various formats
# suitable for display.
#
# Usage:
#   ./cook.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly RAPPOR_SRC=$(cd $THIS_DIR/.. && pwd)

source $RAPPOR_SRC/pipeline/tools-lib.sh


status-files() {
  local dir=$1
  find $dir -name STATUS.txt
}

results-files() {
  local dir=$1
  find $dir -name results.csv
}

count-results() {
  # first field of each line is one of {OK, TIMEOUT, FAIL, SKIPPED}
  status-files "$@" \
    | xargs cat \
    | cut -d ' ' -f 1 \
    | sort | uniq -c | sort -n -r
}

#
# For dist cron job
#

# Combine status of tasks over multiple jobs.  Each row is a task (decode-dist
# invocation).  This has the number of reports.
combine-dist-task-status() {
  local base_dir=${1:-~/rappor/cron}
  local job_dir=${2:-~/rappor/cron/2015-05-22__05-58-01}

  local out=$job_dir/task-status.csv

  # Ignore memory for now.
  time status-files $base_dir | TOOLS-combine-status dist > $out
  echo "Wrote $out"
}

# Create a single dist.csv time series for a GIVEN metric.
combine-dist-results-one() {
  local base_dir=$1
  local job_dir=$2
  local metric_name=$3
  #echo FOO $base_dir $metric_name

  local out_dir=$job_dir/cooked/$metric_name
  mkdir -p $out_dir

  # Glob to capture this specific metric name over ALL job IDs.
  find $base_dir/*/raw/$metric_name -name STATUS.txt \
    | TOOLS-combine-results dist 5 \
    > $out_dir/dist.csv
}

# Creates a dist.csv file for EACH metric.  TODO: Rename one/many
combine-dist-results() {
  local base_dir=${1:-~/rappor/cron}
  local job_dir=${2:-~/rappor/cron/2015-05-22__05-58-01}

  # Direct subdirs of 'raw' are metrics.  Just print filename.
  find $base_dir/*/raw -mindepth 1 -maxdepth 1 -type d -a -printf '%f\n' \
    | sort | uniq \
    | xargs --verbose -n1 -- \
      $0 combine-dist-results-one $base_dir $job_dir
}

# Take the task-status.csv file, which has row key (metric, date).  Writes
# num_reports.csv and status.csv per metric, and a single overview.csv for all
# metrics.
dist-metric-status() {
  local job_dir=${1:-_tmp/results-10}
  local out_dir=$job_dir/cooked

  TOOLS-metric-status dist $job_dir/task-status.csv $out_dir
}

#
# For association analysis cron job
#

combine-assoc-task-status() {
  local base_dir=${1:-~/rappor/chrome-assoc-smoke}
  local job_dir=${2:-$base_dir/smoke1}

  local out=$job_dir/assoc-task-status.csv

  time find $base_dir -name assoc-status.txt \
    | TOOLS-combine-status assoc \
    > $out

  echo "Wrote $out"
}

# Create a single assoc.csv time series for a GIVEN (var1, var2) pair.
combine-assoc-results-one() {
  local base_dir=$1
  local job_dir=$2
  local metric_pair_rel_path=$3

  local out_dir=$job_dir/cooked/$metric_pair_rel_path
  mkdir -p $out_dir

  # Glob to capture this specific metric name over ALL job IDs.
  find $base_dir/*/raw/$metric_pair_rel_path -name assoc-status.txt \
    | TOOLS-combine-results assoc 5 \
    > $out_dir/assoc-results-series.csv
}

# Creates a dist.csv file for EACH metric.  TODO: Rename one/many
combine-assoc-results() {
  local base_dir=${1:-~/rappor/chrome-assoc-smoke}
  local job_dir=${2:-$base_dir/smoke3}

  # Direct subdirs of 'raw' are metrics, and subdirs of that are variable
  # pairs.  Print "$metric_name/$pair_name".
  find $base_dir/*/raw -mindepth 2 -maxdepth 2 -type d -a -printf '%P\n' \
    | sort | uniq \
    | xargs --verbose -n1 -- \
      $0 combine-assoc-results-one $base_dir $job_dir
}

# Take the assoc-task-status.csv file, which has row key (metric, date).  Writes
# num_reports.csv and status.csv per metric, and a single overview.csv for all
# metrics.
assoc-metric-status() {
  local job_dir=${1:-~/rappor/chrome-assoc-smoke/smoke3}
  local out_dir=$job_dir/cooked

  TOOLS-metric-status assoc $job_dir/assoc-task-status.csv $out_dir
}

"$@"
