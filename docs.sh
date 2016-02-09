#!/bin/bash

set -o nounset
set -o pipefail
set -o errexit

./build.sh doc
cp -a $RAPPOR_DEST/_tmp/doc/* ./gh-pages

echo "After commiting changes, you can publish them by running: "
echo "git subtree push --prefix gh-pages origin gh-pages"