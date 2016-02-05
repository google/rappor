#!/usr/bin/python
"""Print a test spec on stdout.

Each line has parmaeters for a test case.  The regtest.sh shell script reads
these lines and runs parallel processes.

We use Python data structures so the test cases are easier to read and edit.
"""

import sys

#
# TEST CONFIGURATION
#

# For gen_sim_input.py
INPUT_PARAMS = {
    # distribution, num unique values, num clients, values per client
    'exp-100k': ('exp', 100, 100000, 1),
    'exp-1m': ('exp', 100, 1000000, 1),
}

# For rappor_sim.py
# 'k, h, m, p, q, f' as in params file.
RAPPOR_PARAMS = {
    # Initial chrome params from 2014.
    # NOTE: fastrand simulation only supports 64 bits!  Make sure to use the
    # 'fast_counts' code path.
    'chrome128': (128, 2, 128, 0.25, 0.75, 0.50),

    # Chrome params from early 2015 -- changed to 8 bit reports.
    'chrome8': (8, 2, 128, 0.25, 0.75, 0.50),

    # Original demo params
    'demo': (16, 2, 64, 0.5, 0.75, 0.5),
}

# For deriving candidates from true inputs.
MAP_PARAMS = {
    # 1. Number of extra candidates to add.
    # 2. Candidate strings to remove from the map.  This FORCES false
    # negatives, e.g. for common strings, since a string has to be in the map
    # for RAPPOR to choose it.
    'add-100': (100, []),
    'add-1000': (1000, []),
    'add-2000': (2000, []),
    # also thrashes on 128 bits
    'add-3000': (3000, []),
    'add-10000': (10000, []),
    'add-15000': (15000, []),  # approx number of candidates for eTLD+1
    'add-100000': (100000, []),
    'remove-top-2': (20, ['v1', 'v2']),
}

# test case name -> (input params name, RAPPOR params name, map params name)
TEST_CASES = [
    ('chrome128-100k-100', 'exp-100k', 'chrome128', 'add-100'),
    ('chrome128-100k-1000', 'exp-100k', 'chrome128', 'add-1000'),
    ('chrome128-100k-2000', 'exp-100k', 'chrome128', 'add-2000'),
    ('chrome128-100k-3000', 'exp-100k', 'chrome128', 'add-3000'),
    # 128 bits and 15k candidates fails on a machine with 8 GB memory.
    # Lasso finishes with 7508 non-zero coefficients, and then allocation
    # fails.  TODO: just take the highest ones?
    #('chrome128-100k-15000', 'exp-100k', 'chrome128', 'add-15000'),
    #('chrome128-100k-100000', 'exp-100k', 'chrome128', 'add-100000'),

    # NOTE: Adding more candidates exercises LASSO
    ('chrome8-100k-100', 'exp-100k', 'chrome8', 'add-100'),
    ('chrome8-100k-1000', 'exp-100k', 'chrome8', 'add-1000'),
    ('chrome8-100k-2000', 'exp-100k', 'chrome8', 'add-2000'),
    ('chrome8-100k-3000', 'exp-100k', 'chrome8', 'add-3000'),
    ('chrome8-100k-15000', 'exp-100k', 'chrome8', 'add-15000'),

    # NOTE: This one takes too much memory!  More than 4 GB.  This is because
    # Lasso gets a huge matrix (100,000).  We got 1564 non-zero coefficients.
    ('chrome8-100k-100000', 'exp-100k', 'chrome8', 'add-100000'),

    # What happens when the the candidates are missing top values?
    ('chrome8-badcand', 'exp-100k', 'chrome8', 'remove-top-2'),

    # TODO: Use chrome params with real map from Alexa 1M ?
]

#
# END TEST CONFIGURATION
#


def main(argv):
  rows = []
  for test_case, input_name, rappor_name, map_name in TEST_CASES:
    input_params = INPUT_PARAMS[input_name]
    rappor_params = RAPPOR_PARAMS[rappor_name]
    map_params = MAP_PARAMS[map_name]
    row = tuple([test_case]) + input_params + rappor_params + map_params
    rows.append(row)

  for row in rows:
    for cell in row:
      if isinstance(cell, list):
        if cell:
          cell_str = '|'.join(cell)
        else:
          cell_str = 'NONE'  # we don't want an empty string
      else:
        cell_str = cell
      print cell_str,  # print it with a space after it
    print  # new line after row


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
