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
  PYTHONPATH=$CLIENT_DIR time \
    tests/rappor_sim.py \
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

# By default, we generate v1..v50.  Add some more here.  We hope these are
# estimated at 0.
more-candidates() {
  cat <<EOF
v51
v52
v53
v54
v55
v56
v57
v58
v59
v60
EOF
}

# Args:
#   dist: which distribution we are running on
#   to_remove: list of values which we "forgot" to include in the candidates
#       list.  Passed to egrep -v, e.g. v1|v2|v3.
print-candidates() {
  local dist=$1
  # Assume that we know the set of true inputs EXACTLY
  #cp _tmp/${dist}_true_inputs.txt _tmp/${dist}_candidates.txt
  #
  local to_remove="$2"  # true values we omitted from the candidates list.

  local in=_tmp/${dist}_true_inputs.txt
  if test -n "$to_remove"; then
    egrep -v "$to_remove" $in  # remove some true inputs
  else
    cat $in  # include all true inputs
  fi
  more-candidates
}

hash-candidates() {
  local dist=$1
  shift
  local out=_tmp/${dist}_map.csv
  PYTHONPATH=$CLIENT_DIR time analysis/tools/hash_candidates.py \
    _tmp/${dist}_params.csv \
    < _tmp/${dist}_candidates.txt \
    > $out
  log "Wrote $out"
}

sum-bits() {
  local dist=$1
  shift
  local out=_tmp/${dist}_counts.csv
  PYTHONPATH=$CLIENT_DIR analysis/tools/sum_bits.py \
    _tmp/${dist}_params.csv \
    < _tmp/${dist}_out.csv \
    > $out
  log "Wrote $out"
}

# Analyze output of Python client library.
analyze() {
  local dist=$1
  local title=$2
  local prefix=_tmp/$dist

  local out_dir=_tmp/${dist}_report
  mkdir -p $out_dir

  # The shebang on analyze.R is /usr/bin/Rscript.  With some Linux distros
  # (Ubuntu), you often need to compile your own R to get say R 3.0 instead of
  # 2.14.  In that case, do something like:
  #
  # export R_SCRIPT=/usr/local/bin/Rscript

  local r_script=${R_SCRIPT:-env}
  time $r_script tests/analyze.R -t "$title" $prefix $out_dir
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

  banner "Generating candidates ($dist)"

  # Example of removing candidates.
  print-candidates $dist 'v1|v2'  > _tmp/${dist}_candidates.txt

  # Keep all candidates
  #print-candidates $dist '' > _tmp/${dist}_candidates.txt

  banner "Hashing Candidates ($dist)"
  hash-candidates $dist

  banner "Summing bits ($dist)"
  sum-bits $dist

  # TODO:
  # guess-candidates  # cheat and get them from the true input
  # hash-candidates  # create map file

  banner "Analyzing RAPPOR output ($dist)"
  analyze $dist "Distribution Comparison ($dist)"
}

expand-html() {
  local template=${1:-../tests/report.html}
  local out_dir=${2:-_tmp}

  pushd $out_dir >/dev/null

  # Add simulation parameters and RAPPOR parameters.
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

  wc -l _tmp/*.csv

  # Expand the HTML skeleton
  expand-html ../tests/report.html _tmp
}

# Main entry point.  Run it for all distributions, and time the result.
run() {
  time _run "$@"
}

"$@"
