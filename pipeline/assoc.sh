#!/bin/bash
#
# Usage:
#   ./assoc.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly RAPPOR_SRC=$(cd $THIS_DIR/.. && pwd)

source $RAPPOR_SRC/util.sh  # log, banner
source $RAPPOR_SRC/pipeline/tools-lib.sh
source $RAPPOR_SRC/pipeline/alarm-lib.sh

# Change the default location of these tools by setting DEP_*
readonly DECODE_ASSOC=${DEP_DECODE_ASSOC:-$RAPPOR_SRC/bin/decode-assoc}
readonly FAST_EM=${DEP_FAST_EM:-$RAPPOR_SRC/analysis/cpp/_tmp/fast_em}

# Run a single decode-assoc process, to analyze one variable pair for one
# metric.  The arguments to this function are one row of the task spec.
decode-one() {
  # Job constants, from decode-many
  local rappor_src=$1
  local timeout_secs=$2
  local min_reports=$3
  local job_dir=$4
  local sample_size=$5

  # Task spec variables, from task_spec.py
  local num_reports=$6
  local metric_name=$7
  local date=$8  # for output naming only
  local reports=$9  # file with reports
  local var1=${10}
  local var2=${11}
  local map1=${12}
  local output_dir=${13}

  local log_file=$output_dir/assoc-log.txt
  local status_file=$output_dir/assoc-status.txt
  mkdir --verbose -p $output_dir

  # Flags drived from job constants
  local schema=$job_dir/config/rappor-vars.csv
  local params_dir=$job_dir/config
  local em_executable=$FAST_EM

  # TODO:
  # - Skip jobs with few reports, like ./backfill.sh analyze-one.

  # Output the spec for combine_status.py.
  echo "$@" > $output_dir/assoc-spec.txt

  # NOTE: Not passing --num-cores since we're parallelizing already.

  # NOTE: --tmp-dir is the output dir.  Then we just delete all the .bin files
  # afterward so we don't copy them to x20 (they are big).

  { time \
      alarm-status $status_file $timeout_secs \
        $DECODE_ASSOC \
          --create-bool-map \
          --remove-bad-rows \
          --em-executable $em_executable \
          --schema $schema \
          --params-dir $params_dir \
          --metric-name $metric_name \
          --reports $reports \
          --var1 $var1 \
          --var2 $var2 \
          --map1 $map1 \
          --reports-sample-size $sample_size \
          --tmp-dir $output_dir \
          --output-dir $output_dir
  } >$log_file 2>&1
}

test-decode-one() {
  decode-one $RAPPOR_SRC
}

readonly DEFAULT_MIN_REPORTS=5000

#readonly DEFAULT_TIMEOUT_SECONDS=300  # 5 minutes as a quick test.
readonly DEFAULT_TIMEOUT_SECONDS=3600  # 1 hour

readonly DEFAULT_MAX_PROCS=6  # TODO: Share with backfill.sh

# Limit to 1M for now.  Raise it when we have a full run.
readonly DEFAULT_SAMPLE_SIZE=1000000

readonly NUM_ARGS=8  # number of tokens in the task spec, used for xargs

# Run many decode-assoc processes in parallel.
decode-many() {
  local job_dir=$1
  local spec_list=$2

  # These 3 params affect speed
  local timeout_secs=${3:-$DEFAULT_TIMEOUT_SECONDS}
  local sample_size=${4:-$DEFAULT_SAMPLE_SIZE}
  local max_procs=${5:-$DEFAULT_MAX_PROCS}

  local rappor_src=${6:-$RAPPOR_SRC}
  local min_reports=${7:-$DEFAULT_MIN_REPORTS}

  time cat $spec_list \
    | xargs --verbose -n $NUM_ARGS -P $max_procs --no-run-if-empty -- \
      $0 decode-one $rappor_src $timeout_secs $min_reports $job_dir $sample_size
}

# Combine assoc results and render HTML.

combine-and-render-html() {
  local jobs_base_dir=$1
  local job_dir=$2

  banner "Combining assoc task status"
  TOOLS-cook combine-assoc-task-status $jobs_base_dir $job_dir

  banner "Combining assoc results"
  TOOLS-cook combine-assoc-results $jobs_base_dir $job_dir

  banner "Splitting out status per metric, and writing overview"
  TOOLS-cook assoc-metric-status $job_dir

  TOOLS-gen-ui symlink-static assoc $job_dir

  banner "Building overview .part.html from CSV"
  TOOLS-gen-ui assoc-overview-part-html $job_dir

  banner "Building metric .part.html from CSV"
  TOOLS-gen-ui assoc-metric-part-html $job_dir

  banner "Building pair .part.html from CSV"
  TOOLS-gen-ui assoc-pair-part-html $job_dir

  banner "Building day .part.html from CSV"
  TOOLS-gen-ui assoc-day-part-html $job_dir
}

# Temp files left over by the fast_em R <-> C++.
list-and-remove-bin() {
  local job_dir=$1
  # If everything failed, we might not have anything to list/delete.
  find $job_dir -name \*.bin | xargs --no-run-if-empty -- ls -l --si
  find $job_dir -name \*.bin | xargs --no-run-if-empty -- rm -f --verbose
}

"$@"
