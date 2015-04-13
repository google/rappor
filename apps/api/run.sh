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

setup() {
  mkdir -p --verbose \
    ~/rappor-api/state \
    ~/rappor-api/logs
}

#
# Tests
#

readonly RAPPOR_SRC=$(cd $PWD/../.. && pwd)

# Run the server in batch mode
get() {
  rappor-api --test-get "$@"
}

post() {
  rappor-api --test-post "$@"
}

health() {
  get /_ah/health
}

sleep() {
  get /sleep seconds=1
}

error() {
  get /error
}

bad-sleep() {
  get /sleep sleepSeconds=BLAH
}

readonly EXP_POST=$RAPPOR_SRC/_tmp/exp_post.json

make-dist-post-body() {
  pushd $RAPPOR_SRC
  local dist=${1:-exp}
  apps/api/testdata.py $dist | tee $EXP_POST
  # TODO: This should be replaced with gsutil
  cp --verbose _tmp/regtest/demo-${dist}/case_map.csv ~/rappor-api/state
  popd
}

dist() {
  make-dist-post-body
  cat $EXP_POST | post /dist
}

curl-dist() {
  local host_port=${1:-localhost:8500}

  time cat $EXP_POST | curl \
    --include \
    --header 'Content-Type: application/json' \
    --data @- \
    http://$host_port/dist
}

curl-vm() {
  . google.sh
  curl-dist $VM_HOST_PORT
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
  rappor-api "$@"
}

#
# Map files
#

# gsutil comes with Google Cloud SDK.  Need 'gcloud auth login'.
gs-list() {
  gsutil ls
}

gs-upload() {
  echo foo > foo.txt
  gsutil cp foo.txt gs://chrome-maps
}

gs-download() {
  echo foo > foo.txt
  gsutil cp gs://chrome-maps/foo.txt foo2.txt
  cat foo2.txt
}

#
# OLD
#

publish-test() {
  cp -v test.sh $EXP_POST /home/andychu/share/rappor
}


"$@"
