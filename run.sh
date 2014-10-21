#!/bin/bash
#
# Miscellaneous scripts.
#
# Usage:
#   ./run.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

# Count lines of code
count() {
  find . \
    -name \*.py -o -name \*.c -o -name \*.h -o -name \*.R -o -name \*.sh \
    | xargs wc -l
}

"$@"
