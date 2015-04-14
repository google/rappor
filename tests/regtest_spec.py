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

DISTRIBUTIONS = (
    'unif',
    'exp',
    'gauss',
    'zipf1',
    'zipf1.5',
)

DISTRIBUTION_PARAMS = (
    # name, num unique values, num clients, values per client
    ('small', 100, 1000000, 1),
    ('medium', 1000, 10000000, 1),
    ('large', 10000, 100000000, 1),
)

# 'k, h, m' as in params file.
BLOOMFILTER_PARAMS = {
    '8x16': (8, 2, 16),  # 16 cohorts, 8 bits each, 2 bits set in each
    '8x32': (8, 2, 32),  # 32 cohorts, 8 bits each, 2 bits set in each
    '8x128': (8, 2, 128),  # 128 cohorts, 8 bits each, 2 bits set in each
    '128x128': (128, 2, 128),  # 8 cohorts, 128 bits each, 2 bits set in each
}

# 'p, q, f' as in params file.
PRIVACY_PARAMS = {
    'eps_1_1': (0.44, 0.56, 0),  # eps_1 = 1, no eps_inf
    'eps_1_5': (0.225, 0.775, 0.0),  # eps_1 = 5, no eps_inf
    'eps_inf_5': (0.39, 0.61, 0.45),  # eps_1 = 1, eps_inf = 5:
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
    ('typical', '128x128', 'eps_1_1', .2, '10%'),
    ('categorical', '128x128', 'eps_1_1', .0, 'sharp'),  # no extra candidates
    ('loose', '128x128', 'eps_1_5', .2, '10%'),  # loose privacy
    ('over_x2', '128x128', 'eps_1_1', 2.0, '10%'),  # overshoot by x2
    ('over_x10', '128x128', 'eps_1_1', 10.0, '10%'),  # overshoot by x10
]

DEMO_CASES = [
    # The 5 cases run by the demo.sh script
    ('demo-small-exp', 'exp_a', '8x128', 'eps_1_1', 20, '10%'),
    ('demo-small-gauss', 'gauss_a', '8x128', 'eps_1_1', 20, '10%'),
]

#
# END TEST CONFIGURATION
#

def CreateOptionsParser():
  p = optparse.OptionParser()

  p.add_option(
      '-r', dest='runs', metavar='INT', type='int', default=1,
      help='Number of runs for each test.')

  return p

def main(argv):
  (opts, argv) = CreateOptionsParser().parse_args(argv)
  rows = []
  
  test_case = []
  for (distr_params, num_values, num_clients, 
      num_reports_per_client) in DISTRIBUTION_PARAMS:
    for distribution in DISTRIBUTIONS:
      for (config_name, bloom_name, privacy_params, fr_extra, 
          regex_missing) in TEST_CONFIGS:
        test_name = '{}-{}-{}'.format(distribution,
            distr_params, config_name)

        params = (BLOOMFILTER_PARAMS[bloom_name]
            + PRIVACY_PARAMS[privacy_params]
            + tuple([int(num_values * fr_extra)])
            + tuple([MAP_REGEX_MISSING[regex_missing]]))

        for r in range(1, opts.runs + 1):
          test_run = (test_name, r, distribution, num_values, num_clients,
              num_reports_per_client)
          row_str = [str(element) for element in test_run + params]
          rows.append(row_str)

  for row in rows:
    print ' '.join(row)

if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
