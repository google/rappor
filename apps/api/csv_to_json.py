#!/usr/bin/python
"""
csv_to_json.py

Convert old CSV format to new JSON format.
"""

import csv
import sys
import json

# Chrome params from 2014
CHROME1 = {
    'numBits': 128,
    'numHashes': 2,
    'numCohorts': 512,
    # TODO: probPrr
    'f': 0.50,
    # TODO: probZero, probOne?
    'p': 0.25,
    'q': 0.75,
}

# Chrome params from early 2015 -- changed to 8 bit reports.
CHROME2 = {
    'numBits': 8,
    'numHashes': 2,
    'numCohorts': 512,
    # TODO: probPrr
    'f': 0.50,
    # TODO: probZero, probOne?
    'p': 0.25,
    'q': 0.75,
}


def main(argv):
  post_body = {}
  counts = []

  # TODO: Add dimensions somewhere?  I guess that is implied by the params.

  with open(argv[1]) as f:
    c = csv.reader(f)
    for row in c:
      counts.append(row)

  post_body = {}
  # Relative path, taken relative to --state-dir

  post_body['candidates_file'] = 'TODO'

  post_body['params'] = CHROME2

  post_body['counts'] = counts
  json.dump(post_body, sys.stdout, indent=2)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
