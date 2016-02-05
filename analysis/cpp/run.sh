#!/bin/bash
#
# Usage:
#   ./run.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

# Call gcc with the flags we like.
# NOTE: -O3 does a lot for fast_em.  (More than 5x speedup over unoptimized)

cpp-compiler() {
  g++ -Wall -Wextra -O3 "$@"
  #clang++ -Wall -Wextra -O3 "$@"
}

build-find-cliques() {
  mkdir -p _tmp
  # C++ 11 for unordered_{map,set}
  cpp-compiler -std=c++0x -o _tmp/find_cliques find_cliques.cc 
}

find-cliques() {
  _tmp/find_cliques "$@"
}

test-bad-edge() {
  # Edge should go from lesser partition number to greater
  find-cliques <<EOF
num_partitions 3
ngram_size 2
edge 1.ab 0.cd
EOF
}

test-bad-size() {
  # Only support n =2 now
  find-cliques <<EOF
num_partitions 3
ngram_size 3
edge 0.ab 1.cd
EOF
}

demo() {
  local graph=${1:-testdata/graph1.txt}
  build-find-cliques

  time cat $graph | find-cliques
}

get-lint() {
  mkdir -p _tmp
  wget --directory _tmp \
    http://google-styleguide.googlecode.com/svn/trunk/cpplint/cpplint.py
  chmod +x _tmp/cpplint.py
}

lint() {
  _tmp/cpplint.py find_cliques.cc fast_em.cc
}

build-fast-em() {
  mkdir -p _tmp
  local out=_tmp/fast_em

  cpp-compiler -o $out fast_em.cc
  ls -l $out
}

fast-em() {
  build-fast-em
  time _tmp/fast_em "$@"
}

"$@"
