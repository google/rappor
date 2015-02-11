#!/bin/bash
#
# Usage:
#   ./run.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

import-web() {
  local src=~/git/poly2/pylib/
  cp -v $src/{web.py,wsgiref_server.py,log.py,hello_web.py} .
}

import-poly() {
  local src=~/hg/polyweb/poly
  cp -v $src/{child.py,app_types.py} .
}

import-r() {
  local src=~/hg/polyweb
  cp -v \
    $src/pgi_lib/pgi.R \
    $src/app_root/examples/uber/pages.R \
    .
}

# For the API server.  Don't need shiny.
install-r-packages() {
  # NOTE: If you run this as root, it will write to /usr/local/lib/R.
  # This can avoid an interactive prompt.
  R -e 'install.packages(c("RJSONIO", "glmnet", "optparse"), repos="http://cran.rstudio.com/")'
}

# Run the server in batch mode
r-smoke-test() {
  ./rappor_api.py --test /_ah/health
}

readonly HEALTH_URL=http://localhost:8500/_ah/health

parallel-test() {
  # TODO: curl the server in parallel, time total
  time seq 3 | xargs -P2 -n1 --verbose -- curl $HEALTH_URL
}

count() {
  wc -l *.py *.R
}

"$@"
