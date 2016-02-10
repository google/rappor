#!/bin/bash
#
# Build automation.
#
# Usage:
#   ./build.sh [function name]
#
# Important targets are:
#   cpp-client: Build the C++ client
#   doc: build docs with Markdown
#   fastrand: build Python extension module to speed up the client simulation
#
# If no function is specified all 3 targets will be built.

set -o nounset
set -o pipefail
set -o errexit

log() {
  echo 1>&2 "$@"
}

die() {
  log "FATAL: $@"
  exit 1
}

run-markdown() {
  local md=`which markdown || echo "cat"`

  # Markdown is output unstyled; make it a little more readable.
  cat <<EOF
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="UTF-8">
      <style type="text/css">
        code { color: green; }
        pre { margin-left: 3em; }
      </style>
      <!-- INSERT LATCH JS -->
    </head>
    <body style="margin: 0 auto; width: 40em; text-align: left;">
      <!-- INSERT LATCH HTML -->
EOF

  $md "$@"

  cat <<EOF
    </body>
  </html>
EOF
}

run-dot() {
  local in=$1
  local out=$2

  local msg="dot not found (perhaps 'sudo apt-get install graphviz')"
  which dot >/dev/null || die "$msg"

  log "Running dot"
  # width, height
  dot \
    -Tpng -Gsize='2,4!' -Gdpi=300 \
    -o $out $in
}

# Scan for TODOs.  Does this belong somewhere else?
todo() {
  find . -name \*.py -o -name \*.R -o -name \*.sh -o -name \*.md \
    | xargs --verbose -- grep -w TODO
}

#
# Targets: build "doc" or "fastrand"
#

# Build dependencies: markdown tool.
doc() {
  mkdir -p _tmp _tmp/doc

  # For now, just one file.
  # TODO: generated docs
  run-markdown <README.md >_tmp/README.html
  run-markdown <doc/randomness.md >_tmp/doc/randomness.html

  run-markdown <doc/data-flow.md >_tmp/doc/data-flow.html
  run-dot doc/data-flow.dot _tmp/doc/data-flow.png

  log 'Wrote docs to _tmp'
}

# Build dependencies: Python development headers.  Most systems should have
# this.  On Ubuntu/Debian, the 'python-dev' package contains headers.
fastrand() {
  pushd tests >/dev/null
  python setup.py build
  # So we can 'import _fastrand' without installing
  ln -s --force build/*/_fastrand.so .
  ./fastrand_test.py

  log 'fastrand built and tests PASSED'
  popd >/dev/null
}

cpp-client() {
  pushd client/cpp
  mkdir --verbose -p _tmp
  make _tmp/rappor_sim  # this builds an executable using it
  popd
}

if test $# -eq 0 ; then
  cpp-client
  doc
  fastrand
else
  "$@"
fi
