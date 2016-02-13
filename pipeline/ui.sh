#!/bin/bash
#
# Build the user interface.
#
# Usage:
#   ./ui.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)
readonly RAPPOR_SRC=$(cd $THIS_DIR/.. && pwd)

source $RAPPOR_SRC/pipeline/tools-lib.sh

# Change the default location of this file by setting DEP_DYGRAPHS_JS
readonly DYGRAPHS_JS=${DEP_DYGRAPHS_JS:-$RAPPOR_SRC/third_party/dygraph-combined.js}

_link() {
  ln --verbose -s -f "$@"
}

_copy() {
  cp --verbose -f "$@"
}

download-dygraphs() {
  local out=third_party
  wget --directory $out \
    http://dygraphs.com/1.1.1/dygraph-combined.js
}

import-table() {
  local src=~/git/scratch/ajax/
  cp --verbose $src/table-sort.{js,css} $src/url-hash.js ui
  pushd ui
  # TODO: Could minify it here
  cat table-sort.js url-hash.js > table-lib.js
  popd
}

# Use symlinks so we can edit and reload during development.
symlink-static() {
  local kind=$1
  local job_dir=$2

  local base=$RAPPOR_SRC/ui

  # HTML goes at the top level.
  if test "$kind" = dist; then
    _link \
      $base/overview.html $base/histograms.html $base/metric.html $base/day.html \
      $job_dir
  elif test "$kind" = assoc; then
    _link \
      $base/assoc-overview.html $base/assoc-metric.html $base/assoc-pair.html \
      $base/assoc-day.html \
      $job_dir
  else 
    log "Invalid kind $kind"
    exit 1
  fi

  mkdir --verbose -p $job_dir/static

  # Static subdir.
  _link \
    $base/ui.css $base/ui.js \
    $base/table-sort.css $base/table-lib.js \
    $DYGRAPHS_JS \
    $job_dir/static
}


# Write HTML fragment based on overview.csv.
overview-part-html() {
  local job_dir=${1:-_tmp/results-10}
  local out=$job_dir/cooked/overview.part.html
  # Sort by descending date!
  TOOLS-csv-to-html \
    --col-format 'metric <a href="metric.html#metric={metric}">{metric}</a>' \
    < $job_dir/cooked/overview.csv \
    > $out
  echo "Wrote $out"
}

metric-part-html() {
  local job_dir=${1:-_tmp/results-10}
  # Testing it out.  This should probably be a different dir.

  for entry in $job_dir/cooked/*; do
    # Only do it for dirs
    if ! test -d $entry; then
      continue
    fi
    # Now it's a metric dir
    echo $entry

    local metric_name=$(basename $entry)

    # Convert status.csv to status.part.html (a fragment)

    # NOTE: counts path could be useful.  You need the input tree though.  Hash
    # it?  Or point to the git link.

    # Link to raw CSV
    #--col-format 'date <a href="../../raw/{metric}/{date}/results.csv">{date}</a>' \

    # TODO: Link to ui/results_viewer.html#{metric}_{date}
    # And that needs some JavaScript to load the correct fragment.
    # I guess you could do the same with metric.html.  Currently it uses a
    # symlink.

    # Before job ID:
    # --col-format 'date <a href="{date}.html">{date}</a>' \
    # --col-format 'status <a href="../../raw/{metric}/{date}/log.txt">{status}</a>' \

    local fmt1='date <a href="day.html#jobId={job_id}&metric={metric}&date={date}">{date}</a>'
    local fmt2='status <a href="../{job_id}/raw/{metric}/{date}/log.txt">{status}</a>'

    TOOLS-csv-to-html \
      --def "metric $metric_name" \
      --col-format "$fmt1" \
      --col-format "$fmt2" \
      < $entry/status.csv \
      > $entry/status.part.html
  done
}

results-html-one() {
  local csv_in=$1
  echo "$csv_in -> HTML"

  # .../raw/Settings.HomePage2/2015-03-01/results.csv ->
  # .../cooked/Settings.HomePage2/2015-03-01.part.html
  # (This saves some directories)
  local html_out=$(echo $csv_in | sed -e 's|/raw/|/cooked/|; s|/results.csv|.part.html|')

  TOOLS-csv-to-html < $csv_in > $html_out
}

results-html() {
  local job_dir=${1:-_tmp/results-10}

  find $job_dir -name results.csv \
    | xargs -n 1 --verbose --no-run-if-empty -- $0 results-html-one
}

# Build parts of the HTML
build-html1() {
  local job_dir=${1:-_tmp/results-10}

  symlink-static dist $job_dir

  # writes overview.part.html, which is loaded by overview.html
  overview-part-html $job_dir

  # Writes status.part.html for each metric
  metric-part-html $job_dir
}

#
# Association Analysis
#

readonly ASSOC_TEST_JOB_DIR=~/rappor/chrome-assoc-smoke/smoke5-assoc

# Write HTML fragment based on CSV.
assoc-overview-part-html() {
  local job_dir=${1:-$ASSOC_TEST_JOB_DIR}
  local html_path=$job_dir/cooked/assoc-overview.part.html

  # Sort by descending date!

  TOOLS-csv-to-html \
    --col-format 'metric <a href="assoc-metric.html#metric={metric}">{metric}</a>' \
    < $job_dir/cooked/assoc-overview.csv \
    > $html_path
  echo "Wrote $html_path"
}

assoc-metric-part-html-one() {
  local csv_path=$1
  local html_path=$(echo $csv_path | sed 's/.csv$/.part.html/')

  local metric_dir=$(dirname $csv_path)
  local metric_name=$(basename $metric_dir)  # e.g. interstitial.harmful

  local fmt='days <a href="assoc-pair.html#metric={metric}&var1={var1}&var2={var2}">{days}</a>'

  TOOLS-csv-to-html \
    --def "metric $metric_name" \
    --col-format "$fmt" \
    < $csv_path \
    > $html_path

  echo "Wrote $html_path"
}

assoc-metric-part-html() {
  local job_dir=${1:-$ASSOC_TEST_JOB_DIR}
  # Testing it out.  This should probably be a different dir.

  find $job_dir/cooked -name metric-status.csv \
    | xargs -n 1 --verbose --no-run-if-empty -- $0 assoc-metric-part-html-one
}

# TODO:
# - Construct link in JavaScript instead?  It has more information.  The
# pair-metadata.txt file is a hack.

assoc-pair-part-html-one() {
  local csv_path=$1
  local html_path=$(echo $csv_path | sed 's/.csv$/.part.html/')

  local pair_dir_path=$(dirname $csv_path)
  local pair_dir_name=$(basename $pair_dir_path)  # e.g. domain_X_flags_IS_REPEAT_VISIT

  # This file is generated by metric_status.R for each pair of variables.
  local metadata="$pair_dir_path/pair-metadata.txt"
  # Read one variable per line.
  { read metric_name; read var1; read var2; } < $metadata

  local fmt1='date <a href="assoc-day.html#jobId={job_id}&metric={metric}&var1={var1}&var2={var2}&date={date}">{date}</a>'
  local fmt2="status <a href=\"../{job_id}/raw/{metric}/$pair_dir_name/{date}/assoc-log.txt\">{status}</a>"

  TOOLS-csv-to-html \
    --def "metric $metric_name" \
    --def "var1 $var1" \
    --def "var2 $var2" \
    --col-format "$fmt1" \
    --col-format "$fmt2" \
    < $csv_path \
    > $html_path
}

assoc-pair-part-html() {
  local job_dir=${1:-~/rappor/chrome-assoc-smoke/smoke3}
  # Testing it out.  This should probably be a different dir.

  find $job_dir/cooked -name pair-status.csv \
    | xargs -n 1 --verbose -- $0 assoc-pair-part-html-one

  return

  # OLD STUFF
  for entry in $job_dir/cooked/*; do
    # Only do it for dirs
    if ! test -d $entry; then
      continue
    fi
    # Now it's a metric dir
    echo $entry

    local metric_name=$(basename $entry)

    # Convert status.csv to status.part.html (a fragment)

    # NOTE: counts path could be useful.  You need the input tree though.  Hash
    # it?  Or point to the git link.

    # Link to raw CSV
    #--col-format 'date <a href="../../raw/{metric}/{date}/results.csv">{date}</a>' \

    # TODO: Link to ui/results_viewer.html#{metric}_{date}
    # And that needs some JavaScript to load the correct fragment.
    # I guess you could do the same with metric.html.  Currently it uses a
    # symlink.

    # Before job ID:
    # --col-format 'date <a href="{date}.html">{date}</a>' \
    # --col-format 'status <a href="../../raw/{metric}/{date}/log.txt">{status}</a>' \

    local fmt1='date <a href="day.html#jobId={job_id}&metric={metric}&date={date}">{date}</a>'
    local fmt2='status <a href="../{job_id}/raw/{metric}/{date}/log.txt">{status}</a>'

    TOOLS-csv-to-html \
      --def "metric $metric_name" \
      --col-format "$fmt1" \
      --col-format "$fmt2" \
      < $entry/status.csv \
      > $entry/status.part.html
  done
}

assoc-day-part-html-one() {
  local csv_in=$1
  echo "$csv_in -> HTML"

  # .../raw/interstitial.harmful/a_X_b/2015-03-01/assoc-results.csv ->
  # .../cooked/interstitial.harmful/a_X_b/2015-03-01.part.html
  # (This saves some directories)
  local html_out=$(echo $csv_in | sed -e 's|/raw/|/cooked/|; s|/assoc-results.csv|.part.html|')

  TOOLS-csv-to-html --as-percent proportion < $csv_in > $html_out
}

assoc-day-part-html() {
  local job_dir=${1:-_tmp/results-10}

  find $job_dir -name assoc-results.csv \
    | xargs -n 1 --verbose --no-run-if-empty -- $0 assoc-day-part-html-one
}

lint-html() {
  set -o xtrace
  set +o errexit  # don't fail fast
  tidy -errors -quiet ui/metric.html
  tidy -errors -quiet ui/overview.html
  tidy -errors -quiet ui/histograms.html
}

# Directory we should serve from
readonly WWW_DIR=_tmp

serve() {
  local port=${1:-7999}
  cd $WWW_DIR && python -m SimpleHTTPServer $port
}

"$@"
