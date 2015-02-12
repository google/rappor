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

#
# Tests
#

readonly RAPPOR_SRC=$(cd $PWD/../.. && pwd)

# Run the server in batch mode
get() {
  export RAPPOR_SRC
  rappor-api --test "$@"
  #./rappor_api.py --test "$@"
}

health() {
  get /_ah/health
}

sleep() {
  get /sleep sleepSeconds=1
}

bad-sleep() {
  get /sleep sleepSeconds=BLAH
}

dist() {
  get /dist
}

readonly HEALTH_URL=http://localhost:8500/_ah/health
readonly SLEEP_URL=http://localhost:8500/sleep

parallel-test() {
  time seq 3 | xargs -P2 -n1 -I{} --verbose -- curl $SLEEP_URL?sleepSeconds={}
}

smoke-test() {
  time seq 3 | xargs -P2 -n1 -I{} --verbose -- curl $HEALTH_URL
}

#
# Misc
#

count() {
  wc -l *.py *.R
}

#
# Serve
#

rappor-api() {
  # R code needs to be able to find other modules
  export RAPPOR_SRC
  ./rappor_api.py "$@"
}

serve() {
  rappor-api --log-dir _tmp/log
}

"$@"
