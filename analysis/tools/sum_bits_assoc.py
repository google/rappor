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
"""

import csv
import sys

import rappor


def SumBits(params, stdin, f_2way, f_1, f_2):
  csv_in = csv.reader(stdin)
  csv_out_two_way = csv.writer(open(f_2way, "w"))
  csv_out_1 = csv.writer(open(f_1, "w"))
  csv_out_2 = csv.writer(open(f_2, "w"))

  num_cohorts = params.num_cohorts
  num_bloombits = params.num_bloombits

  sums = [[0] * (4 * (num_bloombits ** 2)) for _ in xrange(num_cohorts)]
  sums_1 = [[0] * num_bloombits for _ in xrange(num_cohorts)]
  sums_2 = [[0] * num_bloombits for _ in xrange(num_cohorts)]
  num_reports = [0] * num_cohorts

  for i, row in enumerate(csv_in):
    try:
      (user_id, cohort, irr_1, irr_2) = row
    except ValueError:
      raise RuntimeError('Error parsing row %r' % row)

    if i == 0:
      continue  # skip header

    cohort = int(cohort)
    num_reports[cohort] += 1

    # TODO: Extend checking for both reports
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

  SumBits(params, sys.stdin, prefix + "_2way.csv",
          prefix + "_marg1.csv", prefix + "_marg2.csv")


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, e.args[0]
    sys.exit(1)
