#!/usr/bin/python
#
# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Read the RAPPOR'd values on stdin, and sum the bits to produce a Counting Bloom
filter by cohort.  This can then be analyzed by R.
"""

import csv
import sys

import rappor


def SumBits(params, stdin, stdout):
  csv_in = csv.reader(stdin)
  csv_out = csv.writer(stdout)

  num_cohorts = params.num_cohorts
  num_bloombits = params.num_bloombits

  sums = [[0] * num_bloombits for _ in xrange(num_cohorts)]
  num_reports = [0] * num_cohorts

  for i, row in enumerate(csv_in):
    try:
      (user_id, cohort, unused_bloom, unused_prr, irr) = row
    except ValueError:
      raise RuntimeError('Error parsing row %r' % row)

    if i == 0:
      continue  # skip header

    cohort = int(cohort)
    num_reports[cohort] += 1

    if not len(irr) == params.num_bloombits:
      raise RuntimeError(
          "Expected %d bits, got %r" % (params.num_bloombits, len(irr)))
    for i, c in enumerate(irr):
      bit_num = num_bloombits - i - 1  # e.g. char 0 = bit 15, char 15 = bit 0
      if c == '1':
        sums[cohort][bit_num] += 1
      else:
        if c != '0':
          raise RuntimeError('Invalid IRR -- digits should be 0 or 1')

  for cohort in xrange(num_cohorts):
    # First column is the total number of reports in the cohort.
    row = [num_reports[cohort]] + sums[cohort]
    csv_out.writerow(row)


def main(argv):
  try:
    filename = argv[1]
  except IndexError:
    raise RuntimeError('Usage: sum_bits.py <params file>')
  with open(filename) as f:
    try:
      params = rappor.Params.from_csv(f)
    except rappor.Error as e:
      raise RuntimeError(e)

  SumBits(params, sys.stdin, sys.stdout)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, e.args[0]
    sys.exit(1)
