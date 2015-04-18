#!/bin/bash
#
# Copyright 2014 Google Inc. All rights reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Test automation script.
#
# Usage:
#   test.sh <function name>
#
# Examples:
#   $ ./test.sh py-unit  # run Python unit tests
#   $ ./test.sh all      # all tests

set -o nounset
set -o pipefail
set -o errexit

. util.sh

readonly THIS_DIR=$(dirname $0)
readonly REPO_ROOT=$THIS_DIR
readonly CLIENT_DIR=$REPO_ROOT/client/python

#
# Fully Automated Tests
#

# Python unit tests.
#
# TODO: Separate out deterministic tests from statistical tests (which may
# rarely fail)
py-unit() {
  export PYTHONPATH=$CLIENT_DIR  # to find client library

  set +o errexit
  # -e: exit at first failure
  find $REPO_ROOT -name \*_test.py | sh -x -e
  local exit_code=$?
  if test $exit_code -eq 0; then
    echo 'ALL TESTS PASSED'
  else
    echo 'FAIL'
    exit 1
  fi
  set -o errexit
}

# All tests
all() {
  banner "Running Python unit tests"

  py-unit
  echo

  banner "Linting Python source files"
  py-lint

  banner "Running R unit tests"
  r-unit
}

#
# Lint
#

python-lint() {
  # E111: indent not a multiple of 4.  We are following the Google/Chrome style
  # and using 2 space indents.
  if pep8 --ignore=E111 "$@"; then
    echo
    echo 'LINT PASSED'
  else
    echo
    echo 'LINT FAILED'
    exit 1
  fi
}

py-lint() {
  which pep8 >/dev/null || die "pep8 not installed ('sudo apt-get install pep8' on Ubuntu)"

  # - Skip _tmp dir, because we are downloading cpplint.py there, and it has
  # pep8 lint errors
  # - Exclude setup.py, because it's a config file and uses "invalid" 'name =
  # 1' style (spaces around =).
  find $REPO_ROOT \
    \( -name _tmp -a -prune \) -o \
    \( -name \*.py -a -print \) \
    | grep -v /setup.py \
    | xargs --verbose -- $0 python-lint
}

r-unit() {
  set -o xtrace  # show tests we're running

  # This one needs to be run from the root dir
  tests/analyze_test.R

  tests/gen_counts_test.R

  # The way we source requires changing dirs.
  pushd analysis/test >/dev/null
  ./run_tests.R
  popd >/dev/null
}

doc-lint() {
  which tidy >/dev/null || die "tidy not found"
  for doc in _tmp/report.html _tmp/doc/*.html; do
    echo $doc
  # -e: show only errors and warnings
  # -q: quiet
    tidy -e -q $doc || true
  done
}

# This isn't a strict check, but can help.
# TODO: Add words to whitelist.
spell-all() {
  which spell >/dev/null || die "spell not found"
  spell README.md doc/*.md | sort | uniq
}

"$@"
