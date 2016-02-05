#!/bin/bash
#
# Update docs from rappor code located in ../rappor
#
# Usage:
#   ./update.sh 

set -o nounset
set -o pipefail
set -o errexit

readonly RAPPOR_DEST=`readlink -f ../rappor`

die() {
  echo 1>&2 "$@" ; exit 1
}

assert-dest() {
  test -d $1 || die \
    "This requires that the RAPPOR repo is cloned into $1"
}

pushd $RAPPOR_DEST
./build.sh doc
popd

mkdir -p ./doc

cp -a $RAPPOR_DEST/_tmp/doc/* ./doc
