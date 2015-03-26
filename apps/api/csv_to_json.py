#!/usr/bin/python
"""
csv_to_json.py

Convert old CSV format to new JSON format.
"""

import csv
import sys


def main(argv):
  with open(argv[1]) as f:
    c = csv.reader(f)
    print c
    for row in c:
      print row


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
