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
  sudo apt-get install r-base
}

r-packages() {
  # Install as root so you can write to /usr/local/lib/R.
  sudo R -e \
    'install.packages(c("shiny", "ggplot2", "glmnet", "optparse"), repos="http://cran.rstudio.com/")'
}

# After running one of the run_app.sh scripts, see if the app returns a page.
smoke-test() {
  curl http://localhost:6789/
}

# Then set up a "firewall rule" in console.developers.google.com to open up
# "tcp:6789".  Test it from the outside.

"$@"
