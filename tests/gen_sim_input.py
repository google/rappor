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

# Copyright 2014 Google Inc. All Rights Reserved.
"""Tool to generated simulated input data for RAPPOR.

We can output data in the following distributions:

    a. Uniform
    b. Gaussian
    c. Exponential

After it goes through RAPPOR, we should be able see the distribution, but not
any user's particular input data.
"""

import csv
import getopt
import math
import os
import random
import sys
import time

# Distributions
DISTR_UNIF = 1           # Uniform
DISTR_GAUSS = 2          # Gaussian
DISTR_EXP = 3            # Exponential


# Command line arguments
OUTFILE = ""                    # Output file name
NUM_LINES = 0                   # Line mode instead of CSV mode
DISTR = DISTR_UNIF              # Distribution: default is uniform
NUM_UNIQUE_VALUES = 100         # Range of client's values in reports
                                # The default is strings "1" ... "100"
DIST_PARAM = None               # Parameter to pass to distribution
NUM_CLIENTS = 100000            # Number of simulated clients
VALUES_PER_CLIENT = 1


# NOTE: unused.  This is hard-coded now.
LOG_NUM_UNIQUE_VALUES = 30     # Something like 4-5xlog(NUM_UNIQUE_VALUES) bits
                               # should give enough entropy for good samples

ONE_MINUS_EXP_LAMBDA = 0       # 1-e^-lambda


def log(msg, *args):
  if args:
    msg = msg % args
  print >>sys.stderr, msg


def usage(script_name):
  sys.stdout.write("""
  Usage: %s [flags]

  -o        CSV output path (required).  Header is client, value.
  -l        Output a value on each line, without a client
  -r        number of unique values to generate (default 100)
  -d        Distribution (exp, gauss, or unif)
  -n        Number of users (default = 100,000)
  -p        Parameter
            Ignored for uniform
            Std-dev for Gaussian
            Lambda for Exponential

  """ % script_name)


def init_rand_precompute():
  global ONE_MINUS_EXP_LAMBDA
  if DISTR == DISTR_EXP:
    ONE_MINUS_EXP_LAMBDA = 1 - math.exp(-DIST_PARAM)


def rand_sample_unif():
  return random.randrange(1, NUM_UNIQUE_VALUES + 1)


def rand_sample_gauss():
  """Returns a value in [1, NUM_UNIQUE_VALUES] drawn from a Gaussian."""
  mean = float(NUM_UNIQUE_VALUES + 1) / 2
  while True:
    r = random.normalvariate(mean, DIST_PARAM)
    value = int(round(r))
    # Rejection sampling to cut off Gaussian to within [1, NUM_UNIQUE_VALUES]
    if 1 <= value <= NUM_UNIQUE_VALUES:
      break

  return value  # true client value


def rand_sample_exp():
  """Returns a random sample in [1, NUM_UNIQUE_VALUES] drawn from an
  exponential distribution.
  """
  rand_in_cf = random.random()
  # Val sampled from exp distr in [0,1] is CDF^{-1}(unif in [0,1))
  rand_sample_in_01 = (
      -math.log(1 - rand_in_cf * ONE_MINUS_EXP_LAMBDA) / DIST_PARAM)
  # Scale up to NUM_UNIQUE_VALUES and floor to integer
  rand_val = int((rand_sample_in_01 * NUM_UNIQUE_VALUES) + 1)
  return rand_val


PARAMS_HTML = """
  <h3>Simulation Input</h3>
  <table align="center">
    <tr>
      <td>Number of clients</td>
      <td align="right">{num_clients:,}</td>
    </tr>
    <tr>
      <td>Total values reported / obfuscated</td>
      <td align="right">{num_values:,}</td>
    </tr>
    <tr>
      <td>Unique values reported / obfuscated</td>
      <td align="right">{num_unique_values}</td>
    </tr>
  </table>
"""


def WriteParamsHtml(num_values, f):
  d = {
      'num_clients': NUM_CLIENTS,
      'num_unique_values': NUM_UNIQUE_VALUES,
      'num_values': num_values
  }
  # NOTE: No HTML escaping since we're writing numbers
  print >>f, PARAMS_HTML.format(**d)


def main(argv):
  # All command line arguments are placed into global vars
  global OUTFILE, NUM_LINES, NUM_UNIQUE_VALUES, DISTR, DIST_PARAM, \
      NUM_CLIENTS, VALUES_PER_CLIENT

  # Get arguments
  try:
    opts, args = getopt.getopt(argv[1:], "d:n:p:o:r:c:l:")
  except getopt.GetoptError:
    usage(argv[0])
    sys.exit(2)

  # Parsing arguments
  for opt, arg in opts:
    if opt == "-o":
      OUTFILE = arg
    if opt == "-l":
      NUM_LINES = int(arg)
    elif opt == "-r":
      NUM_UNIQUE_VALUES = int(arg)
    elif opt == "-d":
      d = {'exp': DISTR_EXP, 'gauss': DISTR_GAUSS, 'unif': DISTR_UNIF}
      DISTR = d.get(arg)
      if not DISTR:
        raise RuntimeError('Invalid distribution %r' % arg)
    elif opt == "-p":
      DIST_PARAM = float(arg)
    elif opt == "-n":
      NUM_CLIENTS = int(arg)
    elif opt == "-c":
      VALUES_PER_CLIENT = int(arg)

  # NOTE: Output file is required now (instead of using stdout) because it's
  # also used to write sim params.
  if not OUTFILE:
    sys.stdout.write("Output file is required.\n")
    usage(argv[0])
    sys.exit(2)

  if NUM_UNIQUE_VALUES < 2:
    sys.stdout.write("Range should be at least 2. Setting to default 100.\n")
    NUM_UNIQUE_VALUES = 100

  if DIST_PARAM is None:
    if DISTR == DISTR_GAUSS:
      DIST_PARAM = float(NUM_UNIQUE_VALUES) / 6
    elif DISTR == DISTR_EXP:
      DIST_PARAM = float(NUM_UNIQUE_VALUES) / 5

  if NUM_CLIENTS < 10:
    sys.stdout.write("RAPPOR works typically with much larger user sizes.")
    sys.stdout.write(" Setting number of users to 10.\n")
    NUM_CLIENTS = 10

  random.seed()

  # Precompute and initialize constants needed for random samples
  init_rand_precompute()

  # Choose a function that yields the desired distrubtion.  Each of these
  # functions returns a randomly sampled integer between 1 and
  # NUM_UNIQUE_VALUES.  The functions use some globals.
  if DISTR == DISTR_UNIF:
    rand_sample = rand_sample_unif
  elif DISTR == DISTR_GAUSS:
    rand_sample = rand_sample_gauss
  elif DISTR == DISTR_EXP:
    rand_sample = rand_sample_exp

  start_time = time.time()

  # Printing values into file OUTFILE
  with open(OUTFILE, "w") as f:
    if NUM_LINES:
      # In this mode we're not outputting the client
      for i in xrange(NUM_LINES):
        if i % 10000 == 0:
          elapsed = time.time() - start_time
          log('Generated %d rows in %.2f seconds', i, elapsed)

        true_value = 'v%d' % rand_sample()
        print >>f, true_value

    else:  # csv mode
      c = csv.writer(f)
      c.writerow(('client', 'true_value'))
      for i in xrange(1, NUM_CLIENTS + 1):
        if i % 10000 == 0:
          elapsed = time.time() - start_time
          log('Generated %d rows in %.2f seconds', i, elapsed)

        for _ in xrange(VALUES_PER_CLIENT):  # A fixed number of values per user
          true_value = 'v%d' % rand_sample()
          c.writerow((i, true_value))
  log('Wrote %s', OUTFILE)

  prefix, _ = os.path.splitext(OUTFILE)
  params_filename = prefix + '_sim_params.html'
  # TODO: This should take 'opts'
  num_values = NUM_CLIENTS * VALUES_PER_CLIENT
  with open(params_filename, 'w') as f:
    WriteParamsHtml(num_values, f)
  log('Wrote %s', params_filename)


if __name__ == "__main__":
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, e.args[0]
    sys.exit(1)
