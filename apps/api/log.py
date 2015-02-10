#!/usr/bin/python
"""
log.py

Extremely basic logging.  I keep copying this function into every file.

I never really used the log levels.  Not sure if I need it.

This should probably grow to encompass the Poly logging protocol, for:

- showing logs with hierarchical program structure
- showing threads in separate files
  - linking
- pretty printing as HTML
"""

import sys


def info(msg, *args):
  if args:
    msg = msg % args
  print >>sys.stderr, msg


# For now there is no difference.  child.py uses it.
error = info
