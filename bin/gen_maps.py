#!/usr/bin/python
"""
gen_maps.py
"""

import sys
from xml.etree import ElementTree


def main(argv):
  filename = argv[1]
  with open(filename) as f:
    tree = ElementTree.parse(f)
  print tree

  # Why is this a flat list?
  for node in tree.iter():
    print node.tag
    print node.attrib
    print '--'


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
