#!/bin/bash
#
# Build automation.
#
# Usage:
#   ./build.sh <function name>
#
# Important targets are:
#   doc: build docs with Markdown
#   fastrand: build Python extension module to speed up the client simulation

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
  which markdown >/dev/null || die "Markdown not installed"

  # Markdown is output unstyled; make it a little more readable.
  cat <<EOF
  <!DOCTYPE html>
  <html>
    <head>
      <style>
        code { color: green }
      </style>
    </head>
    <body style="margin: 0 auto; width: 40em; text-align: left;">
      <p>
EOF

  markdown "$@"

  cat <<EOF
      </p>
    </body>
  </html>
EOF
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
  run-markdown <doc/tutorial.md >_tmp/doc/tutorial.html
  run-markdown <doc/randomness.md >_tmp/doc/randomness.html

  log 'Wrote docs to _tmp'
}

# Build dependencies: Python development headers.  Most systems should have
# this.  On Ubuntu/Debian, the 'python-dev' package contains headers.
fastrand() {
  pushd client/python >/dev/null
  python setup.py build
  # So we can 'import _fastrand' without installing
  ln -s --force build/*/_fastrand.so .
  ./fastrand_test.py

  log 'fastrand built and tests PASSED'
  popd >/dev/null
}

"$@"
