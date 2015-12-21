#!/bin/bash
#
# Library used to refer to open source tools.

set -o nounset
set -o pipefail
set -o errexit

#
# NOTE: RAPPOR_SRC defined by the module that sources (cook.sh or ui.sh)
#

# These 3 used by cook.sh.

TOOLS-combine-status() {
  $RAPPOR_SRC/pipeline/combine_status.py "$@"
}

TOOLS-combine-results() {
  $RAPPOR_SRC/pipeline/combine_results.py "$@"
}

TOOLS-metric-status() {
  $RAPPOR_SRC/pipeline/metric_status.R "$@"
}

# Used by ui.sh.

TOOLS-csv-to-html() {
  $RAPPOR_SRC/pipeline/csv_to_html.py "$@"
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

