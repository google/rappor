#!/bin/bash
#
# Library used to refer to open source tools.

set -o nounset
set -o pipefail
set -o errexit

# NOTE: RAPPOR_SRC defined by the module that sources (cook.sh or ui.sh)

# Caller can override shebang line by setting $DEP_PYTHON.
readonly PYTHON=${DEP_PYTHON:-}

readonly METRIC_STATUS=${DEP_METRIC_STATUS:-}


# These 3 used by cook.sh.

TOOLS-combine-status() {
  if test -n "$PYTHON"; then
    $PYTHON $RAPPOR_SRC/pipeline/combine_status.py "$@"
  else
    $RAPPOR_SRC/pipeline/combine_status.py "$@"
  fi
}

TOOLS-combine-results() {
  if test -n "$PYTHON"; then
    $PYTHON $RAPPOR_SRC/pipeline/combine_results.py "$@"
  else
    $RAPPOR_SRC/pipeline/combine_results.py "$@"
  fi
}

TOOLS-metric-status() {
  if test -n "$METRIC_STATUS"; then
    $METRIC_STATUS "$@"
  else
    $RAPPOR_SRC/pipeline/metric_status.R "$@"
  fi
}

# Used by ui.sh.

TOOLS-csv-to-html() {
  if test -n "$PYTHON"; then
    $PYTHON $RAPPOR_SRC/pipeline/csv_to_html.py "$@"
  else
    $RAPPOR_SRC/pipeline/csv_to_html.py "$@"
  fi
}

#
# Higher level scripts
#

TOOLS-cook() {
  $RAPPOR_SRC/pipeline/cook.sh "$@"
}

# TODO: Rename gen-ui.sh.
TOOLS-gen-ui() {
  $RAPPOR_SRC/pipeline/ui.sh "$@"
}
