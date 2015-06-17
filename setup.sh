#!/bin/bash
#
# Setup RAPPOR analysis on Ubuntu Trusty (Google Cloud or otherwise).
#
# For the apps/api server, you need 'install-minimal'.  For the regtest, and
# Shiny apps, we need a few more R packages (ggplot2, data.table, etc.).  They
# cause versioning problems, so we keep them separate.
#
# Usage:
#   ./setup.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

native-packages() {
  sudo apt-get update
  # - build-essential for gcc compilers, invoked while installing R packages.
  # - gfortran Fortran compiler needed for glmnet.
  # - libblas-dev needed for limSolve.
  #
  # NOTE: we get R 3.0.2 on Trusty.
  sudo apt-get install build-essential gfortran libblas-dev r-base
}

r-packages() {
  # Install as root so you can write to /usr/local/lib/R.

  # glmnet, limSolve: solvers for decode.R
  # RJSONIO: for analysis_tool.R
  sudo R -e \
    'install.packages(c("glmnet", "optparse", "limSolve", "RUnit", "abind", "RJSONIO"), repos="http://cran.rstudio.com/")'
}

# R 3.0.2 on Trusty is out of date with CRAN, so we need this workaround.
install-plyr-with-friends() {
  mkdir -p _tmp
  wget --directory _tmp \
    http://cran.r-project.org/src/contrib/Archive/Rcpp/Rcpp_0.11.4.tar.gz
  wget --directory _tmp \
    http://cran.r-project.org/src/contrib/Archive/plyr/plyr_1.8.1.tar.gz
  sudo R CMD INSTALL _tmp/Rcpp_0.11.4.tar.gz
  sudo R CMD INSTALL _tmp/plyr_1.8.1.tar.gz 
  sudo R -e \
    'install.packages(c("reshape2", "ggplot2", "data.table"), repos="http://cran.rstudio.com/")'
}

# Keep Shiny separate, since it seems to install a lot of dependencies.
shiny() {
  sudo R -e \
    'install.packages(c("shiny"), repos="http://cran.rstudio.com/")'
}

#
# Batch
#

install-minimal() {
  native-packages
  r-packages
}

# NOTE: hasn't yet been tested on a clean machine.
install-most() {
  install-minimal
  install-plyr-with-friends
}

#
# Shiny Apps / API Server
#

# After running one of the run_app.sh scripts, see if the app returns a page.
shiny-smoke-test() {
  curl http://localhost:6789/
}

# Then set up a "firewall rule" in console.developers.google.com to open up
# "tcp:6789".  Test it from the outside.

"$@"
