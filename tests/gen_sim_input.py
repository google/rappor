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

"""Generated simulated input data for RAPPOR."""

import csv
import getopt
import math
import optparse
import os
import random
import sys
import time


def log(msg, *args):
  if args:
    msg = msg % args
  print >>sys.stderr, msg


class RandUniform(object):
  """Returns a value drawn from the uniform distribution."""

  def __init__(self, num_unique_values):
    self.num_unique_values = num_unique_values

  def __call__(self):
    return random.randrange(1, self.num_unique_values + 1)


class RandGauss(object):
  """Returns a value drawn from a Gaussian."""

  def __init__(self, num_unique_values, dist_param):
    self.num_unique_values = num_unique_values
    self.stddev = dist_param or float(num_unique_values) / 6

  def __call__(self):
    mean = float(self.num_unique_values + 1) / 2
    while True:
      r = random.normalvariate(mean, self.stddev)
      value = int(round(r))
      # Rejection sampling to cut off Gaussian to within [1, num_unique_values]
      if 1 <= value <= self.num_unique_values:
        break

    return value  # true client value


class RandExp(object):
  """Returns a value drawn from an exponential distribution."""

  def __init__(self, num_unique_values, dist_param):
    self.num_unique_values = num_unique_values
    self.lambda_ = dist_param or float(num_unique_values) / 5
    # 1 - e^-lambda
    self.one_minus_exp_lambda = 1 - math.exp(-self.lambda_)

  def __call__(self):
    rand_in_cf = random.random()
    # Val sampled from exp distr in [0,1] is CDF^{-1}(unif in [0,1))
    rand_sample_in_01 = (
        -math.log(1 - rand_in_cf * self.one_minus_exp_lambda) / self.lambda_)
    # Scale up to num_unique_values and floor to integer
    rand_val = int((rand_sample_in_01 * self.num_unique_values) + 1)
    return rand_val


def CreateOptionsParser():
  p = optparse.OptionParser()

  # This will be used for the C++ client
  p.add_option(
      '-l', type='int', metavar='INT', dest='num_lines', default=0,
      help='Instead of a CSV file, output a text file with a value on each '
           'line, and this number of lines.')

  choices = ['exp', 'gauss', 'unif']
  p.add_option(
      '-d', type='choice', dest='dist', default='exp', choices=choices,
      help='Distribution to draw values from (%s)' % '|'.join(choices))

  p.add_option(
      '-u', type='int', metavar='INT',
      dest='num_unique_values', default=100,
      help='Number of unique values to generate.')
  p.add_option(
      '-c', type='int', metavar='INT', dest='num_clients', default=100000,
      help='Number of clients.')
  p.add_option(
      '-v', type='int', metavar='INT', dest='values_per_client', default=1,
      help='Number of values to generate per client.')

  p.add_option(
      '-p', type='float', metavar='FLOAT', dest='dist_param', default=None,
      help='Parameter to distribution.  Ignored for uniform; Std-dev '
           'for Gaussian; Lambda for Exponential.')

  return p


def main(argv):
  (opts, argv) = CreateOptionsParser().parse_args(argv)

  if opts.num_unique_values < 2:
    raise RuntimeError('-u should be at least 2.')

  if opts.num_clients < 10:
    raise RuntimeError("RAPPOR won't work with less than 10 clients")

  random.seed()

  # Choose a function that yields the desired distrubtion.  Each of these
  # functions returns a randomly sampled integer between 1 and
  # opts.num_unique_values.
  if opts.dist == 'unif':
    rand_sample = RandUniform(opts.num_unique_values)
  elif opts.dist == 'gauss':
    rand_sample = RandGauss(opts.num_unique_values, opts.dist_param)
  elif opts.dist == 'exp':
    rand_sample = RandExp(opts.num_unique_values, opts.dist_param)
  else:
    raise AssertionError(opts.dist)

  start_time = time.time()

  # Printing values into file OUTFILE
  f = sys.stdout

  if opts.num_lines:  # line mode, not writing the client column
    for i in xrange(opts.num_lines):
      if i % 10000 == 0:
        elapsed = time.time() - start_time
        log('Generated %d rows in %.2f seconds', i, elapsed)

      true_value = 'v%d' % rand_sample()
      print >>f, true_value

  else:  # csv mode
    c = csv.writer(f)
    c.writerow(('client', 'true_value'))
    for i in xrange(1, opts.num_clients + 1):
      if i % 10000 == 0:
        elapsed = time.time() - start_time
        log('Generated %d rows in %.2f seconds', i, elapsed)

      # A fixed number of values per user
      for _ in xrange(opts.values_per_client):
        true_value = 'v%d' % rand_sample()
        c.writerow((i, true_value))


if __name__ == "__main__":
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, e.args[0]
    sys.exit(1)
