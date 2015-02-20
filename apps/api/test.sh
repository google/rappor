#!/bin/bash
#
# Usage:
#   ./test.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

curl-dist() {
  local host_port=${1:-localhost:8500}

  time cat exp_post.json | curl \
    --include \
    --header 'Content-Type: application/json' \
    --data @- \
    http://$host_port/dist
}

"$@"
