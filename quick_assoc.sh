#!/bin/bash
#
# Quick script to wrap assoc.R
#
# Usage:
#   ./quick_assoc.sh <dir name> [<EM also? T/F>]
#
# For directory name $dir, quick_assoc.sh expects the following files:
#   $dir/map1.csv -- map files
#   $dir/map2.csv
#   $dir/reports.csv -- these are the raw reports
#   $dir/params.csv -- parameters file for first var
#   $dir/params2.csv -- parameters file for second var
#
# At the end, it will output results of the Two Way Algorithm and EM algorithm
# (if EM also is set to T) to stdout
#
# Examples:
# $ ./quick_assoc.sh . T

readonly THIS_DIR=$(dirname $0)
readonly REPO_ROOT=$THIS_DIR
readonly CLIENT_DIR=$REPO_ROOT/client/python
readonly MAP_SUFFIX=map
readonly COUNT_SUFFIX=count

# All the Python tools need this
export PYTHONPATH=$CLIENT_DIR

_run-input() {
  
  # Read reports and compute two way counts
  analysis/tools/sum_bits_assoc.py \
    $1/params.csv $1/params2.csv\
    "$1/$COUNT_SUFFIX" \
    < $1/reports.csv

  # Currently, the summary file shows and aggregates timing of the inference
  # engine, which excludes R's loading time and reading of the (possibly
  # substantial) map file. Timing below is more inclusive.
  TIMEFORMAT='Running analyze.R took %R seconds'

  # Setting up JSON file inp.json in current directory
  json_file="{\
    \"time\":           false,
    \"maps\":           [\"$1/${MAP_SUFFIX}1.csv\",\
                       \"$1/${MAP_SUFFIX}2.csv\"],\
    \"reports\":        \"$1/reports.csv\",\
    \"params\":         \"$1/params.csv\",\
    \"numvars\":        2,\
    \"verbose\":        \"false\",\
    \"counts\":         [\"$1/${COUNT_SUFFIX}_2way.csv\",\
                        \"${COUNT_SUFFIX}_marg1.csv\",\
                        \"${COUNT_SUFFIX}_marg2.csv\"],"

  # Adding EM comparison depending on flag
  if test $2 = T; then
    json_file=$json_file"\"also_em\": true"
  else 
    json_file=$json_file"\"also_em\": false"
  fi
  json_file=$json_file"}"
  echo $json_file > inp.json
  
  time {
    analysis/R/assoc.R --inp inp.json
  }
}

main() {
  dir=$1
  also_em=${2:-F}
  _run-input $dir $also_em
}

main "$@"
