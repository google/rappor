#!/bin/bash
#
# Export RAPPOR analysis code back into Google.
#
# Usage:
#   scripts/g3export.sh <function name> <args>...

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly RAPPOR_SRC=$(cd $THIS_DIR/.. && pwd)
readonly EM_CPP_EXECUTABLE=$RAPPOR_SRC/analysis/cpp/_tmp/fast_em

# These subdirs (or files) in ~/git/rappor contain the analysis code we want to
# export.  We do NOT want the client libraries -- those go in another location.
#
# util.sh is used by the shell scripts in pipeline/

readonly ANALYSIS_ENTRIES='bin analysis pipeline ui util.sh LICENSE'

# Ensure that a dir ends with google3 (or google3/), so we put the files in the
# right place.
ensure-google3() {
  local dir=$1

  if ! expr $dir : '.*google3$\|.*google3/$'; then
    echo "$dir does not end with google3 or google3/"
    exit 1
  fi
}

# Copy a file, making the parent dir.
copy-rel-path() {
  local dest_root=$1
  local rel_path=$2

  local dest=$dest_root/$rel_path
  mkdir --verbose -p $(dirname $dest)
  cp --verbose $rel_path $dest
}

print-analysis-files() {
  git ls-files $ANALYSIS_ENTRIES
}

# Copy analysis code to google3.
analysis() {
  # The destination root to copy to.
  #
  # Example: ~/foo/google3
  local dest_g3=$1
  ensure-google3 $dest_g3

  local dest=$dest_g3/third_party/rappor_analysis

  # Run from the git repository root.
  cd $RAPPOR_SRC

  print-analysis-files | xargs -n 1 -- $0 copy-rel-path $dest
}

print-testdata-files() {
  ls decode-*-test/input/*.csv
}

# Copy testdata to google3.
testdata() {
  local dest_g3=$1
  ensure-google3 $dest_g3

  local dest=$dest_g3/third_party/rappor_analysis/generated_testdata

  local this_script=$RAPPOR_SRC/scripts/g3export.sh

  # Run from the _tmp dir to get the right relative paths.
  pushd $RAPPOR_SRC/_tmp

  print-testdata-files | xargs -n 1 -- $this_script copy-rel-path $dest

  popd
}

usage() {
  cat <<EOF
Usage: $0 <function name> <args>...

Export RAPPOR code to google3.

Examples:

  # Export code to rappor_analysis
  scripts/g3export.sh analysis ~/foo/google3
  
  # Export data to rappor_analysis/testdata
  scripts/g3export.sh testdata ~/foo/google3

The destination path must be a google3 dir, which ensures that the files are
put in the right place.
EOF
  exit 0
}

if test $# = 0; then
  usage
fi

case "$1" in
  # end-user functions
  analysis|testdata)
    "$@"
    ;;
  # function called by xargs
  copy-rel-path)
    "$@"
    ;;
  *)
    usage
    ;;
esac
