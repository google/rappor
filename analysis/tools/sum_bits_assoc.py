#!/usr/bin/python
#
# Copyright 2015 Google Inc. All rights reserved.
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
Read RAPPOR values of 2 variables from stdin.
Read parameters from parameter file and a prefix.

Output counts of bloom filter bits set for each variable (1-way totals)
and counts of pairwise bits set (2-way totals) into files with suffixes
_marg1.csv, _marg2.csv, _2way.csv respectively.

The file formats for each of the files are as follows:
_marg1.csv, _marg2.csv
Each row corresponds to a cohort with:
num reports, total count for bit 1, total count for bit 2, ...

_2way.csv
Each row corresponds to a cohort
The first entry corresponds to total number of reports in that cohort
The next set of values indicate 2 way counts grouped 4 elements at a time:
  the first 4 refer to information about bit 1 of irr1 and bit 1 of irr2
  the next 4 refer to information about bit 1 of irr1 and bit 2 of irr2
  ...
  the next 4 refer to information about bit 1 of irr1 and bit k of irr2
  the next 4 refer to information about bit 2 of irr1 and bit 1 of irr2
  (pairwise information about tuples is stored in a "1st report"-major order)
  ...
  the last 4 refer to information about bit k of irr1 and bit k of irr2

  for each 4-tuple, the values represents the counts for the pair of bits from
  irr1 and irr2 having the value:
  11, 01, 10, and 00, respectively.

  See sum_bits_assoc_test.py for an example
"""

import csv
import sys

import rappor


def SumBits(params, stdin, f_2way, f_1, f_2):
  csv_in = csv.reader(stdin)
  csv_out_two_way = csv.writer(f_2way)
  csv_out_1 = csv.writer(f_1)
  csv_out_2 = csv.writer(f_2)
#  csv_out_two_way = csv.writer(open(f_2way, "w"))
#  csv_out_1 = csv.writer(open(f_1, "w"))
#  csv_out_2 = csv.writer(open(f_2, "w"))

  num_cohorts = params.num_cohorts
  num_bloombits = params.num_bloombits

  sums = [[0] * (4 * (num_bloombits ** 2)) for _ in xrange(num_cohorts)]
  sums_1 = [[0] * num_bloombits for _ in xrange(num_cohorts)]
  sums_2 = [[0] * num_bloombits for _ in xrange(num_cohorts)]
  num_reports = [0] * num_cohorts

  for i, row in enumerate(csv_in):
    try:
      (_, cohort, irr_1, irr_2) = row
    except ValueError:
      raise RuntimeError('Error parsing row %r' % row)

    if i == 0:
      continue  # skip header

    cohort = int(cohort)
    try:
      num_reports[cohort] += 1
    except IndexError:
      raise RuntimeError('Error indexing cohort number %d (num_cohorts is %d) \
                         ' % (cohort, num_cohorts))

    if not len(irr_1) == params.num_bloombits:
      raise RuntimeError(
        "Expected %d bits in report 1, got %r" % 
        (params.num_bloombits, len(irr_1)))
    if not len(irr_2) == params.num_bloombits:
      raise RuntimeError(
        "Expected %d bits in report 2, got %r" % 
        (params.num_bloombits, len(irr_2)))
    # "Unrolled" joint encoding of both reports
    index_array = [[3, 1], [2, 0]]
    for i, c in enumerate(irr_1):
      for j, d in enumerate(irr_2):
        index = 4 * ((num_bloombits - i - 1) * params.num_bloombits +
                     num_bloombits - j - 1)
        try: 
          diff = index_array[int(c)][int(d)]
        except IndexError:
          raise RuntimeError('Invalid IRRs; digits should be 0/1')
        sums[cohort][index + diff] += 1

    for i, c in enumerate(irr_1):
      bit_num = num_bloombits - i - 1  # e.g. char 0 = bit 15, char 15 = bit 0
      if c == '1':
        sums_1[cohort][bit_num] += 1
      else:
        if c != '0':
          raise RuntimeError('Invalid IRRs; digits should be 0/1')

    for i, c in enumerate(irr_2):
      bit_num = num_bloombits - i - 1  # e.g. char 0 = bit 15, char 15 = bit 0
      if c == '1':
        sums_2[cohort][bit_num] += 1
      else:
        if c != '0':
          raise RuntimeError('Invalid IRRs; digits should be 0/1')

  for cohort in xrange(num_cohorts):
    # First column is the total number of reports in the cohort.
    row = [num_reports[cohort]] + sums[cohort]
    csv_out_two_way.writerow(row)
    row = [num_reports[cohort]] + sums_1[cohort]
    csv_out_1.writerow(row)
    row = [num_reports[cohort]] + sums_2[cohort]
    csv_out_2.writerow(row)


def main(argv):
  try:
    filename = argv[1]
    prefix = argv[2]
  except IndexError:
    raise RuntimeError('Usage: sum_bits.py <params file> <prefix>')
  with open(filename) as f:
    try:
      params = rappor.Params.from_csv(f)
    except rappor.Error as e:
      raise RuntimeError(e)

  with open(prefix + "_2way.csv", "w") as f_2way:
    with open(prefix + "_marg1.csv", "w") as f_1:
      with open(prefix + "_marg2.csv", "w") as f_2:
        SumBits(params, sys.stdin, f_2way, f_1, f_2)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, e.args[0]
    sys.exit(1)
