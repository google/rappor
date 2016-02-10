#!/bin/bash
#
# Usage:
#   ./dist.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly RAPPOR_SRC=$(cd $THIS_DIR/.. && pwd)

source $RAPPOR_SRC/util.sh  # log, banner
source $RAPPOR_SRC/pipeline/tools-lib.sh
source $RAPPOR_SRC/pipeline/alarm-lib.sh

readonly DECODE_DIST=${DEP_DECODE_DIST:-$RAPPOR_SRC/bin/decode-dist}

readonly NUM_ARGS=7  # used for xargs

decode-dist-one() {
  # Job constants
  local rappor_src=$1
  local timeout_secs=$2
  local min_reports=$3
  shift 3  # job constants do not vary per task and are not part of the spec

  # 7 spec variables
  local num_reports=$1  # unused, only for filtering
  local metric_name=$2
  local date=$3
  local counts=$4
  local params=$5
  local map=$6
  local results_dir=$7

  local task_dir=$results_dir/$metric_name/$date
  mkdir --verbose -p $task_dir

  local log_file=$task_dir/log.txt
  local status_file=$task_dir/STATUS.txt

  # Record the spec so we know params, counts, etc.
  echo "$@" > $task_dir/spec.txt

  if test $num_reports -lt $min_reports; then
    local msg="SKIPPED because $num_reports reports is less than $min_reports"
    # Duplicate this message
    echo "$msg" > $status_file
    echo "$msg" > $log_file
    return
  fi

  # Run it with a timeout, and record status in the task dir.
  { time \
      alarm-status $status_file $timeout_secs \
        $DECODE_DIST \
          --counts $counts \
          --params $params \
          --map $map \
          --output-dir $task_dir \
          --adjust-counts-hack
  } >$log_file 2>&1

  # TODO: Don't pass --adjust-counts-hack unless the user asks for it.
}

# Print the number of processes to use.
# NOTE: This is copied from google/rappor regtest.sh.
# It also doesn't take into account the fact that we are memory-bound.
#
# 128 GiB / 4GiB would also imply about 32 processes though.
num-processes() {
  local processors=$(grep -c ^processor /proc/cpuinfo || echo 4)
  if test $processors -gt 1; then  # leave one CPU for the OS
    processors=$(expr $processors - 1)
  fi
  echo $processors
}

#readonly DEFAULT_MAX_PROCS=6  # for andychu2.hot, to avoid locking up UI
#readonly DEFAULT_MAX_PROCS=16  # for rappor-ac.hot, to avoid thrashing
readonly DEFAULT_MAX_PROCS=$(num-processes)

#readonly DEFAULT_MAX_TASKS=12
readonly DEFAULT_MAX_TASKS=10000  # more than the max

# NOTE: Since we have 125 GB RAM, and processes can take up to 12 gigs of RAM,
# only use parallelism of 10, even though we have 31 cores.

readonly DEFAULT_MIN_REPORTS=5000


decode-dist-many() {
  local job_dir=$1
  local spec_list=$2
  local timeout_secs=${3:-1200}  # default timeout
  local max_procs=${4:-$DEFAULT_MAX_PROCS}
  local rappor_src=${5:-$RAPPOR_SRC}
  local min_reports=${6:-$DEFAULT_MIN_REPORTS}

  local interval_secs=5
  local pid_dir="$job_dir/pids"
  local sys_mem="$job_dir/system-mem.csv"
  mkdir --verbose -p $pid_dir

  time cat $spec_list \
    | xargs --verbose -n $NUM_ARGS -P $max_procs --no-run-if-empty -- \
      $0 decode-dist-one $rappor_src $timeout_secs $min_reports
}

# Combine/summarize results and task metadata from the parallel decode-dist
# processes.  Render them as HTML.
combine-and-render-html() {
  local jobs_base_dir=$1
  local job_dir=$2

  banner "Combining dist task status"
  TOOLS-cook combine-dist-task-status $jobs_base_dir $job_dir

  banner "Combining dist results"
  TOOLS-cook combine-dist-results $jobs_base_dir $job_dir

  banner "Splitting out status per metric, and writing overview"
  TOOLS-cook dist-metric-status $job_dir

  # The task-status.csv file should have the a JOB ID.
  banner "Building overview.html and per-metric HTML"
  TOOLS-gen-ui build-html1 $job_dir

  banner "Building individual results.html (for ONE day)"
  TOOLS-gen-ui results-html $job_dir
}

"$@"
