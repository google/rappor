#!/bin/bash
#
# Usage:
#   ./setup.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

# Install all R packages used by any program in the repo.

# NOTE: Conslidate with gce-setup.sh?
#
# We're installing as root since there doesn't seem to be an easy way to
# non-interactively install R libraries as non-root on Ubuntu Trusty.  Setting
# R_LIBS_USER doesn't seem to work.

install-r-packages() {
  sudo R -e 'install.packages(c("shiny", "ggplot2", "glmnet", "optparse", "RUnit"), repos="http://cran.rstudio.com/")'
}

"$@"
