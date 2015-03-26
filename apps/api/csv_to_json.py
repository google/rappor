#!/usr/bin/python
"""
csv_to_json.py

Convert old CSV format to new JSON format.
"""

import csv
import sys
import json


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

  params = {}
  post_body['params'] = params

  post_body['counts'] = counts
  json.dump(post_body, sys.stdout, indent=2)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
