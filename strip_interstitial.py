#!/usr/bin/python
#
# Usage: ./strip_interstitial.py 2015-07-24_interstitial.csv > 7-24-data.csv
#

import csv
import sys

def main(argv):
  try:
    filename = argv[1]
  except IndexError:
    raise RuntimeError('Usage: sum_bits.py <filename>')

  # Read parameter files
  with open(filename) as f:
    csv_in = csv.reader(f)
    csv_out = csv.writer(sys.stdout)
    csv_out.writerow(('client','cohort','irr1','irr2'))
    for i, row in enumerate(csv_in):
      if i == 0:
        continue
      try:
        (cohort, _, _, irr1, _, irr2, _) = row
      except ValueError:
        raise RuntimeError('Error parsing row %r' % row)
      csv_out.writerow((i,int(cohort) % 128, irr1, irr2))

if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, e.args[0]
    sys.exit(1)
