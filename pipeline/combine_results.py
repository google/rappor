#!/usr/bin/python
"""Combines results from multiple days of a single metric.

Feed it the STATUS.txt files on stdin.  It then finds the corresponding
results.csv, and takes the top N items.

Example:

Date,      "google.com,", yahoo.com
2015-03-01,          0.0,       0.9
2015-03-02,          0.1,       0.8

Dygraphs can load this CSV file directly.

TODO: Use different dygraph API?

Also we need error bars.

  new Dygraph(document.getElementById("graphdiv2"),
              [
                [1,10,100],
                [2,20,80],
                [3,50,60],
                [4,70,80]
              ],
              {
                labels: [ "Date", "failure", "timeout", "google.com" ]
              });
"""

import collections
import csv
import json
import os
import sys

import util


def CombineDistResults(stdin, c_out, num_top):
  dates = []
  var_cols = collections.defaultdict(dict)  # {name: {date: value}}

  seen_dates = set()

  for line in stdin:
    status_path = line.strip()

    # Assume it looks like .../2015-03-01/STATUS.txt
    task_dir = os.path.dirname(status_path)
    date = os.path.basename(task_dir)

    # Get rid of duplicate dates.  These could be caused by retries.
    if date in seen_dates:
      continue

    seen_dates.add(date)

    with open(status_path) as f:
      status = f.readline().split()[0]  # OK, FAIL, TIMEOUT, SKIPPED

    dates.append(date)

    if status != 'OK':
      continue  # won't have results.csv

    results_path = os.path.join(task_dir, 'results.csv')
    with open(results_path) as f:
      c = csv.reader(f)
      unused_header = c.next()  # header row

      # they are sorted by decreasing "estimate", which is what we want
      for i in xrange(0, num_top):
        try:
          row = c.next()
        except StopIteration:
          # It's OK if it doesn't have enough
          util.log('Stopping early. Fewer than %d results to render.', num_top)
          break

        string, _, _, proportion, _, prop_low, prop_high = row

        # dygraphs has a weird format with semicolons:
        # value;lower;upper,value;lower;upper.

        # http://dygraphs.com/data.html#csv

        # Arbitrarily use 4 digits after decimal point (for dygraphs, not
        # directly displayed)
        dygraph_triple = '%.4f;%.4f;%.4f' % (
            float(prop_low), float(proportion), float(prop_high))

        var_cols[string][date] = dygraph_triple

  # Now print CSV on stdout.
  cols = sorted(var_cols.keys())  # sort columns alphabetically
  c_out.writerow(['date'] + cols)

  dates.sort()

  for date in dates:
    row = [date]
    for col in cols:
      cell = var_cols[col].get(date)  # None mean sthere is no row
      row.append(cell)
    c_out.writerow(row)

  #util.log("Number of dynamic cols: %d", len(var_cols))


def CombineAssocResults(stdin, c_out, num_top):
  header = ('dummy',)
  c_out.writerow(header)


def main(argv):
  action = argv[1]

  if action == 'dist':
    num_top = int(argv[2])  # number of values to keep
    c_out = csv.writer(sys.stdout)
    CombineDistResults(sys.stdin, c_out, num_top)

  elif action == 'assoc':
    num_top = int(argv[2])  # number of values to keep
    c_out = csv.writer(sys.stdout)
    CombineAssocResults(sys.stdin, c_out, num_top)

  else:
    raise RuntimeError('Invalid action %r' % action)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
