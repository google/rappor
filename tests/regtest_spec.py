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
    'exp1': ('exp', 100, 100000, 7),
    'gauss1': ('gauss', 100, 100000, 7),
    'unif1': ('unif', 100, 100000, 7),
}

# For rappor_sim.py
# 'k, h, m, p, q, f' as in params file.
RAPPOR_PARAMS = {
    # Initial chrome params from 2014.
    # NOTE: fastrand simulation only supports 64 bits!
    #'chrome1': (128, 2, 512, 0.25, 0.75, 0.50),

    # Chrome params from early 2015 -- changed to 8 bit reports.
    'chrome2': (8, 2, 512, 0.25, 0.75, 0.50),

    # Original demo params
    'demo': (16, 2, 64, 0.5, 0.75, 0.5),
}

# For deriving candidates from true inputs.
MAP_PARAMS = {
    # 1. Number of extra candidates to add.
    # 2. Candidate strings to remove from the map.  This FORCES false
    # negatives, e.g. for common strings, since a string has to be in the map
    # for RAPPOR to choose it.
    'demo': (20, []),
    'remove-top-2': (20, ['v1', 'v2']),
}

# test case name -> (input params name, RAPPOR params name, map params name)
TEST_CASES = [
    # The 3 cases in the demo.sh script
    ('demo-exp', 'exp1', 'demo', 'demo'),
    ('demo-gauss', 'gauss1', 'demo', 'demo'),
    ('demo-unif', 'unif1', 'demo', 'demo'),

    # Using Chrome params with synthetic map
    ('chrome2-exp', 'exp1', 'chrome2', 'demo'),

    # What happens when the the candidates are missing top values?
    ('chrome2-badcand', 'exp1', 'chrome2', 'remove-top-2'),

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
