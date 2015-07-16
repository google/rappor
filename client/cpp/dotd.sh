#!/bin/bash
#
# dotd.sh
#
# Generate .d Makefile fragments, so we can use #include statements in source
# for dependency info.  Adapted from the GNU make manual:
#
# http://www.gnu.org/software/make/manual/html_node/Automatic-Prerequisites.html
#
# We are putting this in shell, so we just have 'sed in bash'.  Not an unholy
# mix of 'sed in bash in Make'.

set -o nounset
set -o pipefail
set -o errexit

# Munge gcc -MM output into .d files.
main() {
  local basename=$1
  local dotd=$2  # .d output name
  shift 2  # rest of args are gcc invocation

  local tmp="${dotd}.$$"

  rm --verbose -f $dotd

  # The make file passes some gcc -MM invocation that we will transform.
  "$@" > $tmp

  # Change
  #   rappor_sim.o: rappor.sim.cc
  # to
  #   _tmp/rappor_sim.o _tmp/rappor_sim.d : rappor.sim.cc

  sed "s|\($basename\).o|_tmp/\1.o _tmp/\1.d |" \
    < $tmp \
    > $dotd
}

main "$@"
