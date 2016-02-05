#!/bin/bash
#
# Quick script to wrap assoc.R for boolean.
#
# Usage:
#   ./quick_assoc_boolean.sh <dir name> [<reports file name>]
#
# For directory name $dir, quick_assoc_boolean.sh expects the following files:
#   $dir/map.csv -- map file
#   $dir/reports.csv -- these are the raw reports
#   $dir/params.csv -- parameters file for first var
#   ONLY NEEDED FOR 2WAY ALGORITHM
#   $dir/params2.csv -- parameters file for second var
#
# At the end, it will output results of the EM algorithm to stdout and
# results.csv
#
# Examples:
# If your files lie in data/csv, run
# $ ./quick_assoc_boolean.sh data/csv/

readonly THIS_DIR=$(dirname $0)
readonly REPO_ROOT=$THIS_DIR
readonly CLIENT_DIR=$REPO_ROOT/client/python
readonly MAP_SUFFIX=map
readonly COUNT_SUFFIX=boolcount

# All the Python tools need this
export PYTHONPATH=$CLIENT_DIR

_run-input() {
  
  # Read reports and compute two way counts
  # Uncomment when kinks in 2way algorithm are ironed out
  #  analysis/tools/sum_bits_assoc.py \
  #    $1/params.csv $1/params2.csv\
  #    "$1/$COUNT_SUFFIX" \
  #    < $1/reports.csv

  # Currently, the summary file shows and aggregates timing of the inference
  # engine, which excludes R's loading time and reading of the (possibly
  # substantial) map file. Timing below is more inclusive.
  TIMEFORMAT='Running analyze.R took %R seconds'

  # Setting up JSON file inp.json in current directory
  json_file="{\
    \"time\":           false,
    \"maps\":           [\"$1/${MAP_SUFFIX}.csv\",\
                       \"$1/${MAP_SUFFIX}.csv\"],\
    \"reports\":        \"$1/$2\",\
    \"params\":         \"$1/params.csv\",\
    \"numvars\":        2,\
    \"verbose\":        \"false\",
    \"results\":        \"${2}.results.txt\",
    \"algo\":           \"EM\"}"  # Replace "EM" with "2Way" for new alg
  # Uncomment when kinks in 2way algorithm are ironed out
  #    \"counts\":         [\"$1/${COUNT_SUFFIX}_2way.csv\",\
  #                        \"$1/${COUNT_SUFFIX}_marg1.csv\",\
  #                        \"$1/${COUNT_SUFFIX}_marg2.csv\"],"

  echo $json_file > inp.json
  
  time {
    analysis/R/assoc.R --inp inp.json
  }
}

main() {
  if test $# -eq 0; then
    echo "Usage: ./quick_assoc_boolean.sh <dir name>. Directory must have map,\
reports, and params file (parameters for both vars resp.)."
  else
    dir=$1
    reports_file_name=${2:-"reports.csv"}
    _run-input $dir $reports_file_name
  fi
}

main "$@"
