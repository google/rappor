#!/usr/bin/python
"""testdata.py - Create a POST body from regtest.sh data."""

import json
import os
import sys


def main(argv):
  dist = argv[1]  # NOTE: unused because the demo uses demo1..5 now.
  map_file = argv[2]

  #params_path = '_tmp/regtest/demo-%s/case_params.json' % dist
  #counts_path = '_tmp/regtest/demo-%s/case_counts.json' % dist

  params_path = '_tmp/regtest/demo1/1/case_params.json'
  counts_path = '_tmp/regtest/demo1/1/case_counts.json'

  with open(params_path) as p:
    with open(counts_path) as c:
      params = json.load(p)
      counts = json.load(c)

  post_body = {}
  # Relative path, taken relative to --state-dir
  post_body['candidates_file'] = map_file
  post_body['params'] = params
  post_body.update(counts)
  json.dump(post_body, sys.stdout, indent=2)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
