#!/usr/bin/python
"""
csv_to_json.py

Convert old CSV format to new JSON format.

See also testdata.py.
"""

import csv
import sys
import json

# https://chromium.googlesource.com/chromium/src/+/master/tools/metrics/rappor/rappor.xml

# Chrome params from 2014
CHROME1 = {
    'numBits': 128,
    'numHashes': 2,
    'numCohorts': 128,
    'probPrr': 0.50,  # f, fake-prob
    'probIrr0': 0.25,  # p, zero-coin-prob
    'probIrr1': 0.75,  # q, one-coin-prob
}

# Chrome params from early 2015 -- changed to 8 bit reports.
CHROME2 = {
    'numBits': 8,
    'numHashes': 2,
    'numCohorts': 128,
    'probPrr': 0.50,  # f
    'probIrr0': 0.25,  # p
    'probIrr1': 0.75,  # q
}


def main(argv):
  counts_csv = argv[1]
  map_file = argv[2]

  post_body = {}

  num_reports = []
  sums = []

  # TODO: Add dimensions somewhere?  I guess that is implied by the params.

  # Counts CSV is (m rows) * (k+1 cols).  First column is for the total.

  num_rows = 0
  num_cols = 0

  with open(counts_csv) as f:
    c = csv.reader(f)
    for row in c:
      num_reports.append(int(row[0]))
      # Row-wise sum
      sums.append([int(cell) for cell in row[1:]])
      num_rows += 1

      if num_cols == 0:
        num_cols = len(row)
      else:
        if len(row) != num_cols:
          raise RuntimeError('Expected %d rows, got %d' % (num_cols, len(row)))

  params = CHROME2

  if num_cols != params['numBits'] + 1:
    raise RuntimeError(
        'Got %d cols, but k+1 = %d' % (num_cols, params['numBits'] + 1))

  # Sanity check
  if num_rows != params['numCohorts']:
    raise RuntimeError(
        'Got %d rows, but m = %d' % (num_rows, params['numCohorts']))

  post_body = {}
  # Relative path, taken relative to --state-dir

  # TODO: map is the HASHED candidates.
  post_body['candidates_file'] = map_file

  post_body['params'] = params

  post_body['num_reports'] = num_reports

  post_body['sums'] = sums

  json.dump(post_body, sys.stdout, indent=2)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
