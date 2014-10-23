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
Read the output of the RAPPOR simulation, and simply sum bits to produce a
Counting Bloom filter.  file), which can be analyzed by R.
"""

import sys


class Error(Exception):
  pass


# Update rappor sum
def update_rappor_sums(rappor_sum, rappor, cohort, params):
  for bit_num in xrange(params.num_bloombits):
    if rappor & (1 << bit_num):
      rappor_sum[cohort][1 + bit_num] += 1
  rappor_sum[cohort][0] += 1  # The 0^th entry contains total reports in cohort

def dummy():
  # Print sums of all rappor bits into output file
  with open(inst.outfile, 'w') as f:
    for row in xrange(params.num_cohorts):
      for col in xrange(params.num_bloombits):
        f.write(str(rappor_sums[row][col]) + ",")
      f.write(str(rappor_sums[row][params.num_bloombits]) + "\n")

  # Initializing array to capture sums of rappors.
  rappor_sums = [[0] * (params.num_bloombits + 1)
                 for _ in xrange(params.num_cohorts)]

      # Sum rappors.  TODO: move this to separate tool.
  rappor.update_rappor_sums(rappor_sums, r, cohort, params)
  return rappor_sums




def main(argv):
  """Returns an exit code."""
  # TODO: need to read params file?
  num_cohorts = 64
  num_bloombits = 16
  sums = [[0] * num_bloombits for _ in xrange(num_cohorts)]
  num_reports = [0] * num_cohorts

  for line in sys.stdin:
    parts = line.split(',')
    user_id, encoded = parts[0], parts[1:]
    for e in encoded:
      cohort, irr = e.split()
      cohort = int(cohort)

      num_reports[cohort] += 1

      for bit_num, c in enumerate(irr):
        if c == '1':
          sums[cohort][bit_num] += 1
        else:
          if c != '0':
            raise Error('Invalid IRR -- digits should be 0 or 1')
    #print line

  #f = sys.stdout
  for cohort in xrange(num_cohorts):
    # First column is the total number of reports in the cohort.
    row = [num_reports[cohort]] + sums[cohort]
    print ','.join(str(cell) for cell in row)

  return 0


if __name__ == '__main__':
  try:
    sys.exit(main(sys.argv))
  except Error, e:
    print >> sys.stderr, e.args[0]
    sys.exit(1)
