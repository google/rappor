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
Given a list of candidates on stdin, produce a file of hashes ("map file").
"""

import csv
import sys

import rappor


def HashCandidates(params, stdin, stdout):
  num_bloombits = params.num_bloombits
  csv_out = csv.writer(stdout)

  for line in stdin:
    word = line.strip()
    row = [word]
    for cohort in xrange(params.num_cohorts):
      bloom_bits = rappor.get_bloom_bits(word, cohort, params.num_hashes,
                                         num_bloombits)
      for bit_to_set in bloom_bits:
        # bits are indexed from 1.  Add a fixed offset for each cohort.
        # NOTE: This detail could be omitted from the map file format, and done
        # in R.
        row.append(cohort * num_bloombits + (bit_to_set + 1))
    csv_out.writerow(row)


def main(argv):
  try:
    filename = argv[1]
  except IndexError:
    raise RuntimeError('Usage: hash_candidates.py <params file>')
  with open(filename) as f:
    try:
      params = rappor.Params.from_csv(f)
    except rappor.Error as e:
      raise RuntimeError(e)

  HashCandidates(params, sys.stdin, sys.stdout)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, e.args[0]
    sys.exit(1)
