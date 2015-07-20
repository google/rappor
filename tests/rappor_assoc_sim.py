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

"""Tool to run RAPPOR on simulated client input.

TODO: fill up

Input columns: client,true_value
Ouput coumns: client,cohort,rappor
"""

import csv
import collections
import optparse
import os
import random
import sys
import time

import rappor  # client library
try:
  import fastrand
except ImportError:
  print >>sys.stderr, (
      "Native fastrand module not imported; see README for speedups")
  fastrand = None


def log(msg, *args):
  if args:
    msg = msg % args
  print >>sys.stderr, msg


def CreateOptionsParser():
  p = optparse.OptionParser()

  p.add_option(
      '--num-bits', type='int', metavar='INT', dest='num_bits', default=16,
      help='Number of bloom filter bits.')
  p.add_option(
      '--num-hashes', type='int', metavar='INT', dest='num_hashes', default=2,
      help='Number of hashes.')
  p.add_option(
      '--num-cohorts', type='int', metavar='INT', dest='num_cohorts',
      default=64, help='Number of cohorts.')

  p.add_option(
      '-p', type='float', metavar='FLOAT', dest='prob_p', default=1,
      help='Probability p')
  p.add_option(
      '-q', type='float', metavar='FLOAT', dest='prob_q', default=1,
      help='Probability q')
  p.add_option(
      '-f', type='float', metavar='FLOAT', dest='prob_f', default=1,
      help='Probability f')

  choices = ['simple', 'fast']
  p.add_option(
      '-r', type='choice', metavar='STR',
      dest='random_mode', default='fast', choices=choices,
      help='Random algorithm (%s)' % '|'.join(choices))

  return p

def main(argv):
  (opts, argv) = CreateOptionsParser().parse_args(argv)

  # Copy flags into params
  params = rappor.Params()
  params.num_bloombits = opts.num_bits
  params.num_hashes = opts.num_hashes
  params.num_cohorts = opts.num_cohorts
  params.prob_p = opts.prob_p
  params.prob_q = opts.prob_q
  params.prob_f = opts.prob_f

  if opts.random_mode == 'simple':
    irr_rand = rappor.SimpleIrrRand(params)
  elif opts.random_mode == 'fast':
    if fastrand:
      log('Using fastrand extension')
      # NOTE: This doesn't take 'rand'.  It's seeded in C with srand().
      irr_rand = fastrand.FastIrrRand(params)
    else:
      log('Warning: fastrand module not importable; see README for build '
          'instructions.  Falling back to simple randomness.')
      irr_rand = rappor.SimpleIrrRand(params)
  else:
    raise AssertionError
  # Other possible implementations:
  # - random.SystemRandom (probably uses /dev/urandom on Linux)
  # - HMAC-SHA256 with another secret?  This could match C++ byte for byte.
  #   - or srand(0) might do it.

  csv_in = csv.reader(sys.stdin)
  csv_out = csv.writer(sys.stdout)

  # NOTE: We can also modify the output to include
  # bloombits and the prr for each variable.
  # This is useful for debugging purposes
  header = ('client', 'cohort', 'irr1', 'irr2')
  csv_out.writerow(header)

  # TODO: It would be more instructive/efficient to construct an encoder
  # instance up front per client, rather than one per row below.
  start_time = time.time()

  for i, (client_str, cohort_str, true_value_1, true_value_2) in
                                                          enumerate(csv_in):
    if i == 0:
      if client_str != 'client':
        raise RuntimeError('Expected client header, got %s' % client_str)
      if cohort_str != 'cohort':
        raise RuntimeError('Expected cohort header, got %s' % cohort_str)
      if true_value_1 != 'value1':
        raise RuntimeError('Expected value1 header, got %s' % value)
      if true_value_2 != 'value2':
        raise RuntimeError('Expected value2 header, got %s' % value)
      continue  # skip header row

    #if i == 30:  # EARLY STOP
    #  break

    if i % 10000 == 0:
      elapsed = time.time() - start_time
      log('Processed %d inputs in %.2f seconds', i, elapsed)

    cohort = int(cohort_str)
    secret = client_str
    e = rappor.Encoder(params, cohort, secret, irr_rand)

    # For testing purposes, call e._internal_encode()
    irr_1 = e.encode(true_value_1)
    irr_2 = e.encode(true_value_2)

    irr_1_str = rappor.bit_string(irr_1, params.num_bloombits)
    irr_2_str = rappor.bit_string(irr_2, params.num_bloombits)

    out_row = (cohort_str, irr_1_str, irr_2_str)
    csv_out.writerow(out_row)


if __name__ == "__main__":
  try:
    main(sys.argv)
  except RuntimeError, e:
    log('rappor_sim.py: FATAL: %s', e)
