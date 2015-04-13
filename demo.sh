#!/bin/bash
#
# Demo of RAPPOR.  Automating Python and R scripts.  See README.
#
# Usage:
#   ./demo.sh <function name>
#
# End to end demo for 3 distributions:
#
#   $ ./demo.sh run
#
# This takes a minute or so.  It runs a subset of tests from regtest.sh and
# writes an HTML summary.

set -o nounset
set -o pipefail
set -o errexit

. util.sh

readonly THIS_DIR=$(dirname $0)
readonly REPO_ROOT=$THIS_DIR
readonly CLIENT_DIR=$REPO_ROOT/client/python

# All the Python tools need this
export PYTHONPATH=$CLIENT_DIR

#
# Semi-automated demos
#

# Run rappor-sim through the Python profiler.
rappor-sim-profile() {
  local dist=$1
  shift

  # For now, just dump it to a text file.  Sort by cumulative time.
  time python -m cProfile -s cumulative \
    tests/rappor_sim.py \
    -i _tmp/$dist.csv \
    "$@" \
    | tee _tmp/profile.txt
}

# Build prerequisites for the demo.
build() {
  # This is optional; the simulation will fall back to pure Python code.
  ./build.sh fastrand
}

# Main entry point that is documented in README.md.
run() {
  # Run all the test cases that start with "demo-", and write to "report.html".
  # (The original demo.sh used "report.html", so we're not changing the name.)
  ./regtest.sh run-seq '^demo-' report.html
}

# TODO: Port these old bad cases to regtest_spec.py.

# Running the demo of the exponential distribution with 10000 reports (x7,
# which is 70000 values).
#
# - There are 50 real values, but we add 1000 more candidates, to get 1050 candidates.
# - And then we remove the two most common strings, v1 and v2.
# - With the current analysis, we are getting sum(proportion) = 1.1 to 1.7

# TODO: Make this sharper by including only one real value?

bad-case() {
  local num_additional=${1:-1000}
  run-dist exp 10000 $num_additional 'v1|v2'
}

# Force it to be less than 1
pcls-test() {
  USE_PCLS=1 bad-case
}

# Only add 10 more candidates.  Then we properly get the 0.48 proportion.
ok-case() {
  run-dist exp 10000 10 'v1|v2'
}

"$@"
