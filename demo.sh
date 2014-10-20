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
# Run demo for just one distribution (no HTML output):
#
#   $ ./demo.sh run-dist [exp|gauss|unif]
#
# (This takes a minute or so)

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly REPO_ROOT=$THIS_DIR
readonly CLIENT_DIR=$REPO_ROOT/client/python

#
# Utility functions
#

banner() {
  echo
  echo "----- $@"
  echo
}

log() {
  echo 1>&2 "$@"
}

die() {
  log "$0: $@"
  exit 1
}

#
# Semi-automated demos
#

# This generates the simulated input s1 .. s<n> with 3 different distributions.
gen-sim-input() {
  local dist=$1
  local num_clients=$2

  local flag=''
  case $dist in
    exp)
      flag=-e
      ;;
    gauss)
      flag=-g
      ;;
    unif)
      flag=-u
      ;;
    *)
      die "Invalid distribution '$dist'"
  esac

  mkdir -p _tmp

  # Simulating 10,000 clients runs reasonably fast but the results look poor.
  # 100,000 is slow but looks better.
  # 50 different client values are easier to plot (default is 100)
  time tests/gen_sim_input.py $flag \
    -n $num_clients \
    -r 50 \
    -o _tmp/$dist.csv
}

# Do the RAPPOR transformation on our simulated input.
rappor-sim() {
  local dist=$1
  shift
  PYTHONPATH=$CLIENT_DIR time $REPO_ROOT/tests/rappor_sim.py \
    -i _tmp/$dist.csv \
    "$@"
    #-s 0  # deterministic seed
}

# Like rappor-sim, but run it through the Python profiler.
rappor-sim-profile() {
  local dist=$1
  shift

  export PYTHONPATH=$CLIENT_DIR
  # For now, just dump it to a text file.  Sort by cumulative time.
  time python -m cProfile -s cumulative \
    tests/rappor_sim.py \
    -i _tmp/$dist.csv \
    "$@" \
    | tee _tmp/profile.txt
}

# Analyze output of Python client library.
analyze() {
  local dist=$1
  local title=$2
  local prefix=_tmp/$dist

  local out_dir=_tmp/${dist}_report
  mkdir -p $out_dir

  time tests/analyze.R -t "$title" $prefix $out_dir
}

# Run end to end for one distribution.
run-dist() {
  local dist=$1
  # TODO: parameterize output dirs by num_clients
  local num_clients=${2:-100000}

  banner "Generating simulated input data ($dist)"
  gen-sim-input $dist $num_clients

  banner "Running RAPPOR ($dist)"
  rappor-sim $dist

  banner "Analyzing RAPPOR output ($dist)"
  analyze $dist "Distribution Comparison ($dist)"
}

expand-html() {
  local template=${1:-../tests/report.html}
  local out_dir=${2:-_tmp}

  pushd $out_dir >/dev/null

  # NOTE: We're arbitrarily using the "exp" values since params are all
  # independent of distribution.

  cat $template \
    | sed -e '/SIM_PARAMS/ r exp_sim_params.html' \
          -e '/RAPPOR_PARAMS/ r exp_params.html' \
    > report.html

  log "Wrote $out_dir/report.html.  Open this in your browser."

  popd >/dev/null
}

# Build prerequisites for the demo.
build() {
  # This is optional now.
  ./build.sh fastrand
}

_run() {
  local num_clients=${1:-100000}
  for dist in exp gauss unif; do
    run-dist $dist $num_clients
  done
  # Link the HTML skeleton
  #
  # TODO:
  # - gen_sim_input output sim_params.html
  # - read params rappor_params.html

  expand-html ../tests/report.html _tmp

  wc -l _tmp/*.csv
}

# Main entry point.  Run it for all distributions, and time the result.
run() {
  time _run "$@"
}

"$@"
