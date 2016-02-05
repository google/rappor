#!/bin/bash
#
# Miscellaneous scripts.
#
# Usage:
#   ./run.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

. util.sh

# Count lines of code
count() {
  # exclude _tmp dirs, and include Python, C, C++, R, shell
  find . \
    \( -name _tmp -a -prune \) -o \
    \( -name \*.py -a -print \) -o \
    \( -name \*.c -a -print \) -o \
    \( -name \*.h -a -print \) -o \
    \( -name \*.cc -a -print \) -o \
    \( -name \*.R -a -print \) -o \
    \( -name \*.sh -a -print \) \
    | xargs wc -l | sort -n
}

#
# Publish docs
#

readonly DOC_DEST=../rappor-gh-pages

assert-dest() {
  test -d $DOC_DEST || die \
    "This requires that the RAPPOR repo is cloned into $DOC_DEST"
}

publish-report() {
  assert-dest

  local dest=$DOC_DEST/examples
  mkdir -p $dest

  cp --verbose --recursive \
    _tmp/report.html \
    _tmp/*_report \
    $dest

  echo "Now switch to $DOC_DEST, commit, and push."
}

publish-doc() {
  assert-dest

  local dest=$DOC_DEST/doc
  mkdir -p $dest

  cp --verbose \
    _tmp/doc/*.html \
    _tmp/doc/*.png \
    $dest

  echo "Now switch to $DOC_DEST, commit, and push."
}

"$@"
