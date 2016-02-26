"""Common functions."""

import sys


def log(msg, *args):
  if args:
    msg = msg % args
  print >>sys.stderr, msg
