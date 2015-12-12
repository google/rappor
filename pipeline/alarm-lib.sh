#!/bin/bash
#
# Alarm tool.
#
# Usage:
#   ./alarm.sh <function name>

# You can source this file and use the alarm-status function.

set -o nounset
set -o pipefail
set -o errexit

# Run a command with a timeout, and print its status to a directory.
#
# Usage:
#   alarm-status job_dir/STATUS 10 \
#     flaky_command ...

alarm-status() {
  set +o errexit
  local status_file=$1
  shift  # everything except the status file goes to perl

  # NOTE: It would be nice to setpgrp() before exec?  And then can the signal
  # be delivered to the entire group, like kill -SIGALRM -PID?

  # NOTE: If we did this in Python, the error message would also be clearer.
  perl -e 'alarm shift; exec @ARGV or die "ERROR: after exec @ARGV"' "$@" 
  local exit_code=$?

  set -o errexit

  local result=''
  case $exit_code in
    0)
      # Would be nice to show elapsed time?
      result='OK'
      ;;
    9)
      # decode_assoc.R will exit 9 if there are no reports AFTER
      # --remove-bad-rows.  A task can also be marked SKIPPED before running
      # the child process (see backfill.sh).
      result='SKIPPED by child process'
      ;;
    # exit code 142 means SIGALARM.  128 + 14 = 142.  See 'kill -l'.
    142)
      local seconds=$1
      result="TIMEOUT after $seconds seconds"
      ;;
    *)
      result="FAIL with status $exit_code"
      ;;
  esac
  echo "$result"
  echo "$result" > $status_file
}

_work() {
  local n=10  # 2 seconds
  for i in $(seq $n); do
    echo $i - "$@"
    sleep 0.2
  done
}

_succeed() {
  _work "$@"
  exit 0
}

_fail() {
  _work "$@"
  exit 1
}

_skip() {
  exit 9
}

# http://perldoc.perl.org/functions/alarm.html
#
# Delivers alarm.  But how to get the process to have a distinct exit code?

demo() {
  mkdir -p _tmp

  # timeout
  alarm-status _tmp/A 1 $0 _succeed foo
  echo

  # ok
  alarm-status _tmp/B 3 $0 _succeed bar
  echo

  # fail
  alarm-status _tmp/C 3 $0 _fail baz
  echo

  # skip
  alarm-status _tmp/D 3 $0 _skip baz
  echo

  head _tmp/{A,B,C,D}
}

test-simple() {
  alarm-status _tmp/status.txt 1 sleep 2
}

test-bad-command() {
  alarm-status _tmp/status.txt 1 nonexistent_sleep 2
}

# BUG
test-perl() {
  set +o errexit
  perl -e 'alarm shift; exec @ARGV or die "ERROR after exec @ARGV"' 1 _sleep 2
  echo $?
}

if test $(basename $0) = 'alarm-lib.sh'; then
  "$@"
fi
