#!/bin/bash
#
# Usage:
#   ./setup.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

# Install all R packages used by any program in the repo.

# NOTE: Conslidate with gce-setup.sh?  That installs as root to write to
# /usr/local/lib/R.  Here we don't need that.  It also doesn't install stuff
# like RUnit, which isn't needed on the server.

install-r-packages() {
  R -e 'install.packages(c("shiny", "ggplot2", "glmnet", "optparse", "RUnit"), repos="http://cran.rstudio.com/")'
}

"$@"
