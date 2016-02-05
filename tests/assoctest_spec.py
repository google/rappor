#!/usr/bin/python
"""Print a test spec on stdout.

Each line has parameters for a test case.  The assoctest.sh shell script reads
these lines and runs parallel processes.

We use Python data structures so the test cases are easier to read and edit.
"""

import optparse
import sys

DISTRIBUTION_PARAMS_ASSOC = {
    # name, num unique values 1,
    # num unique values 2, num clients
    'tiny': (100, 2, int(1e03)),   # test for insufficient data
    'small': (100, 10, int(1e04)),
#    'fizz-tiny': (100, 20, int(1e03)),
#    'fizz-tiny-bool': (100, 2, int(1e03)),
#    'fizz-small': (100, 20, int(1e04)),
#    'fizz-small-bool': (100, 2, int(1e04)),
#    'fizz': (100, 20, int(1e05)),
#    'fizz-large': (100, 50, int(1e05)),
#    'fizz-2large': (100, 50, int(5e05)),
#    'fizz-bool': (100, 2, int(1e05)),
    'medium': (1000, 10, int(1e05)),
    'medium2': (1000, 2, int(1e05)),
    'large': (10000, 10, int(1e06)),
    'large2': (10000, 2, int(1e06)),
    'largesquared': (int(1e04), 100, int(1e06)),

    # new test names for 2-way marginals
    # includes testing for extras
    'fizz-tiny': (100, 20, int(1e03), int(1e04)),
    'fizz-tiny-bool': (100, 2, int(1e03), int(1e04)),
    'fizz-small': (100, 20, int(1e04), int(1e04)),
    'fizz-small-bool': (100, 2, int(1e04), int(1e04)),
    'fizz': (100, 20, int(1e05), int(1e04)),
    'fizz-bool': (100, 2, int(1e05), int(1e04)),

    'toy': (5, 2, 1e04, 20),  # for testing purposes only
    'compact-noextra-small': (40, 5, 1e04, 0),
    'loose-noextra-small': (100, 20, 1e04, 0),
    'compact-noextra-large': (40, 5, 1e06, 0),
    'loose-noextra-large': (100, 20, 1e06, 0),
    'compact-extra-small': (40, 5, int(1e04), int(1e04)),
    'loose-extra-small': (100, 20, int(1e04), int(1e04)),
    'compact-extra-large': (40, 5, int(1e06), int(1e04)),
    'loose-extra-large': (100, 20, int(1e06), int(1e04)),
    'compact-excess-small': (40, 5, int(1e04), int(1e05)),
    'loose-excess-small': (100, 20, int(1e04), int(1e05)),
    'compact-excess-large': (40, 5, int(1e06), int(1e05)),
    'loose-excess-large': (100, 20, int(1e06), int(1e05)),
}

# 'k, h, m' as in params file.
BLOOMFILTER_PARAMS = {
    '8x16': (8, 2, 16),  # 16 cohorts, 8 bits each, 2 bits set in each
    '8x32': (8, 2, 32),  # 32 cohorts, 8 bits each, 2 bits set in each
    '16x32': (16, 2, 32),  # 32 cohorts, 16 bits each, 2 bits set in each
    '8x128': (8, 2, 128),  # 128 cohorts, 8 bits each, 2 bits set in each
    '128x128': (128, 2, 128),  # 8 cohorts, 128 bits each, 2 bits set in each
}

# 'p, q, f' as in params file.
PRIVACY_PARAMS = {
    'eps_zero': (0, 0.99, 0),  # testing purposes only!
    'eps_1_1': (0.39, 0.61, 0.45),  # eps_1 = 1, eps_inf = 5:
    'eps_1_5': (0.225, 0.775, 0.0),  # eps_1 = 5, no eps_inf
    'eps_verysmall': (0.125, 0.875, 0.125),
    'eps_small': (0.125, 0.875, 0.5),
    'eps_chrome': (0.25, 0.75, 0.5),
    'uma_rappor_type': (0.50, 0.75, 0.5),
}

# assoc test configuration ->
#   (distribution params set, bloomfilter params set,
#    privacy params set)
# The test config runs a test suite that is the cross product of all the above
# sets
ASSOC_TEST_CONFIG = {
  'distr': (
#            'fizz-tiny',
#            'fizz-tiny-bool',
#            'fizz-small',
#            'fizz-small-bool',
#            'fizz',
#            'fizz-bool',),
#            'toy',),
            'compact-noextra-small',),
#            'loose-noextra-small',),
#            'compact-extra-small',
#            'loose-extra-small',
#            'compact-excess-small',
#            'loose-excess-small',),
#            'compact-noextra-large',
#            'loose-noextra-large',
#            'compact-extra-large',
#            'loose-extra-large',
#            'compact-excess-large',
#            'loose-excess-large'),
  'blooms': (
             '8x32',),
#             '16x32',),
  'privacy': (
              'eps_small',
              'eps_chrome',)
}

#
# END TEST CONFIGURATION
#

def main(argv):
  rows = []
  test_case = []
  # Association tests
  for distr in ASSOC_TEST_CONFIG['distr']:
    for blooms in ASSOC_TEST_CONFIG['blooms']:
      for privacy in ASSOC_TEST_CONFIG['privacy']:
        print distr, blooms, privacy
        test_name = 'a-{}-{}-{}'.format(distr, blooms, privacy)
        params = (BLOOMFILTER_PARAMS[blooms] +
                  PRIVACY_PARAMS[privacy])
        test_case = (test_name,) + DISTRIBUTION_PARAMS_ASSOC[distr] + params
        row_str = [str(element) for element in test_case]
        rows.append(row_str)

  for row in rows:
    print ' '.join(row)

if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
