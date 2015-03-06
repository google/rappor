#!/bin/bash
#
# Usage:
#   ./run.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

build() {
  # for unordered_{map,set}
  g++ -std=c++0x -o find_cliques find_cliques.cc 
}

test-bad-edge() {
  # Edge should go from lesser partition number to greater
  ./find_cliques <<EOF
num_partitions 3
ngram_size 2
edge 1.ab 0.cd
EOF
}

test-bad-size() {
  # Only support n =2 now
  ./find_cliques <<EOF
num_partitions 3
ngram_size 3
edge 0.ab 1.cd
EOF
}

demo() {
  local graph=${1:-testdata/graph1.txt}
  build

  time cat $graph | ./find_cliques
}

get-lint() {
  mkdir -p _tmp
  wget --directory _tmp \
    http://google-styleguide.googlecode.com/svn/trunk/cpplint/cpplint.py
  chmod +x _tmp/cpplint.py
}

lint() {
  _tmp/cpplint.py find_cliques.cc
}

"$@"
