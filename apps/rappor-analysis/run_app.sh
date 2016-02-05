#!/bin/sh
#
# Run the Shiny app in this directory.
#
# Usage:
#   ./run_app.sh [port]

app_dir=$(dirname $0)
port=${1:-6789}

# host= makes it serve to other machines, not just localhost.
exec R --vanilla --slave -e "shiny::runApp('$app_dir', host='0.0.0.0', port=$port)"
