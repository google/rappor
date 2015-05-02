#!/bin/bash
#
# Setup apps on Ubuntu Trusty on GCE.
#
# Usage:
#   ./gce-setup.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

# Install R.  We get R 3.0.2 on Trusty.
native-packages() {
  sudo apt-get update
  # Need build-essential for gcc compilers, invoked while installing R packages.
  # gfortran needed for glmnet.
  sudo apt-get install build-essential gfortran r-base
}

r-packages() {
  # Install as root so you can write to /usr/local/lib/R.
  sudo R -e \
    'install.packages(c("glmnet", "optparse", "RUnit"), repos="http://cran.rstudio.com/")'

  # Leaving out ggplot2 for now.  It has the plyr dependency issue on Trusty.
  # r-cran-plyr is too old.
  #'install.packages(c("ggplot2"), repos="http://cran.rstudio.com/")'
}

# Keep Shiny separate, since it seems to install a lot of dependencies.
shiny() {
  sudo R -e \
    'install.packages(c("shiny"), repos="http://cran.rstudio.com/")'
}

# After running one of the run_app.sh scripts, see if the app returns a page.
shiny-smoke-test() {
  curl http://localhost:6789/
}

# Then set up a "firewall rule" in console.developers.google.com to open up
# "tcp:6789".  Test it from the outside.

"$@"
