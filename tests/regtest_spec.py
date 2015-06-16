#!/usr/bin/python
"""Print a test spec on stdout.

Each line has parameters for a test case.  The regtest.sh shell script reads
these lines and runs parallel processes.

We use Python data structures so the test cases are easier to read and edit.
"""

import optparse
import sys

#
# TEST CONFIGURATION
#

DEMO = (
    # (case_name distr num_unique_values num_clients values_per_client)
    # (num_bits num_hashes num_cohorts)
    # (p q f) (num_additional regexp_to_remove)
    ('demo1 unif    100 10000 10', '16 2 64', '0.1 0.9 0.2', '10 v[0-9]*9$'),
    ('demo2 gauss   100 10000 10', '16 2 64', '0.1 0.9 0.2', '10 v[0-9]*9$'),
    ('demo3 exp     100 10000 10', '16 2 64', '0.1 0.9 0.2', '10 v[0-9]*9$'),
    ('demo4 zipf1   100 10000 10', '16 2 64', '0.1 0.9 0.2', '10 v[0-9]*9$'),
    ('demo5 zipf1.5 100 10000 10', '16 2 64', '0.1 0.9 0.2', '10 v[0-9]*9$'),
)

DISTRIBUTIONS = (
    'unif',
    'exp',
    'gauss',
    'zipf1',
    'zipf1.5',
)

DISTRIBUTION_PARAMS = (
    # name, num unique values, num clients, values per client
    ('tiny', 100, 1000, 1),  # test for insufficient data
    ('small', 100, 1000000, 1),
    ('medium', 1000, 10000000, 1),
    ('large', 10000, 100000000, 1),
)

DISTRIBUTION_PARAMS_ASSOC = {
    # name, num unique values 1,
    # num unique values 2, num clients
    'tiny': (100, 2, int(1e03)),   # test for insufficient data
    'small': (100, 10, int(1e04)),
    'fizz-tiny': (100, 20, int(1e03)),
    'fizz-tiny-bool': (100, 2, int(1e03)),
    'fizz-small': (100, 20, int(1e04)),
    'fizz-small-bool': (100, 2, int(1e04)),
    'fizz': (100, 20, int(1e05)),
    'fizz-large': (100, 50, int(1e05)),
    'fizz-2large': (100, 50, int(5e05)),
    'fizz-bool': (100, 2, int(1e05)),
    'medium': (1000, 10, int(1e05)),
    'medium2': (1000, 2, int(1e05)),
    'large': (10000, 10, int(1e06)),
    'large2': (10000, 2, int(1e06)),
    'largesquared': (int(1e04), 100, int(1e06)),
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
    'eps_1_1': (0.39, 0.61, 0.45),  # eps_1 = 1, eps_inf = 5:
    'eps_1_5': (0.225, 0.775, 0.0),  # eps_1 = 5, no eps_inf
    'eps_verysmall': (0.125, 0.875, 0.125),
    'eps_small': (0.125, 0.875, 0.5),
    'uma_rappor_type': (0.50, 0.75, 0.5),
}

# For deriving candidates from true inputs.
MAP_REGEX_MISSING = {
    'sharp': 'NONE',  # Categorical data
    '10%': 'v[0-9]*9$',  # missing every 10th string
}

# test configuration ->
#   (name modifier, Bloom filter, privacy params, fraction of extra,
#    regex missing)
TEST_CONFIGS = [
    ('typical', '8x128', 'eps_1_1', .2, '10%'),
    ('sharp', '8x128', 'eps_1_1', .0, 'sharp'),  # no extra candidates
    ('loose', '8x128', 'eps_1_5', .2, '10%'),  # loose privacy
    ('over_x2', '8x128', 'eps_1_1', 2.0, '10%'),  # overshoot by x2
    ('over_x10', '8x128', 'eps_1_1', 10.0, '10%'),  # overshoot by x10
]

# assoc test configuration ->
#   (distribution params set, bloomfilter params set,
#    privacy params set)
# The test config runs a test suite that is the cross product of all the above
# sets
ASSOC_TEST_CONFIG = {
    'distr': (#'fizz-tiny',
              #'fizz-small',
              'fizz',),#'fizz-large','fizz-2large'),# 'medium'),
    'blooms': ('8x16', '8x32'), # '8x32', '16x32'),
    'privacy': ('eps_small','uma_rappor_type'),#'uma_rappor_type'), # 'eps_small'),
}

#
# END TEST CONFIGURATION
#


def main(argv):
  rows = []

  test_case = []
  for (distr_params, num_values, num_clients,
       num_reports_per_client) in DISTRIBUTION_PARAMS:
    for distribution in DISTRIBUTIONS:
      for (config_name, bloom_name, privacy_params, fr_extra,
           regex_missing) in TEST_CONFIGS:
        test_name = 'r-{}-{}-{}'.format(distribution, distr_params,
                                        config_name)

        params = (BLOOMFILTER_PARAMS[bloom_name]
                  + PRIVACY_PARAMS[privacy_params]
                  + tuple([int(num_values * fr_extra)])
                  + tuple([MAP_REGEX_MISSING[regex_missing]]))

        test_case = (test_name, distribution, num_values, num_clients,
                     num_reports_per_client) + params
        row_str = [str(element) for element in test_case]
        rows.append(row_str)

  for params in DEMO:
    rows.append(params)

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
  # End of association tests

  for row in rows:
    print ' '.join(row)

if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
