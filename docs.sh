#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit


build() {
  ./build.sh doc
}

copy() {
  cp -a ./_tmp/doc/* ./gh-pages/doc/
  echo "After commiting changes, you can publish them by running: ./docs.sh publish"
}

publish() {
  git subtree push --prefix gh-pages origin gh-pages
}

if test $# -eq 0 ; then
  build
  copy
else
  "$@"
fi


