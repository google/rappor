#!/usr/bin/python
"""
testdata.py - Simple Script to create a test POST.
"""

import json
import os
import sys


def main(argv):
  dist = argv[1]
  with open('_tmp/%s_params.json' % dist) as p:
    with open('_tmp/%s_counts.json' % dist) as c:
      params = json.load(p)
      counts = json.load(c)

  # TODO:
  # - Add candidates.
  # - Should it be JSON or a file?

  post_body = {}
  # Relative path, taken relative to --state-dir
  post_body['candidates_file'] = '%s_map.csv' % dist
  post_body['params'] = params
  post_body.update(counts)
  json.dump(post_body, sys.stdout, indent=2)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
