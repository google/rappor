#!/bin/bash
#
# Munge gcc -MM output into .d files.

set -o nounset
set -o pipefail
set -o errexit

# From:
#
# http://www.gnu.org/software/make/manual/html_node/Automatic-Prerequisites.html#Automatic-PrerequisitesR
#
# We are putting this in shell, so we just have 'sed in bash'.  Not an unholy
# mix of 'sed in bash in Make'.

main() {
  local basename=$1
  local dotd=$2  # .d output name
  shift 2  # rest of args are gcc invocation

  local tmp="${dotd}.$$"

  set -x

  rm --verbose -f $dotd

  "$@" > $tmp

  # Change
  #   rappor_sim.o: rappor.sim.cc
  # to
  #   _tmp/rappor_sim.o _tmp/rappor_sim.d: rappor.sim.cc

  # Can't use / in sed because $basename or $out might have a /

  sed "s|\($basename\)\.o[ :]*|_tmp/\1.o $dotd : |g" \
    < $tmp \
    > $dotd
}

main "$@"
