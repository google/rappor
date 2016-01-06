#!/usr/bin/python
"""
gen_maps.py
"""

import csv
import sys
from xml.etree import ElementTree


def main(argv):
  rappor_vars = argv[1]
  config_path = argv[2]

  # TODO: Make name -> params lookup
  with open(rappor_vars) as f:
    c = csv.reader(f)
    for row in c:
      print row

  with open(config_path) as f:
    tree = ElementTree.parse(f)
  print tree

  # Why is this a flat list?
  for node in tree.iter('metrics'):
    #print dir(node)

    print node.tag
    print node.attrib

    print '--'
    for metric in node.iter('rappor-metric'):
      print metric.attrib

      metric_name = metric.attrib.get('name')
      print 'NAME', metric_name

      for c in metric.iter('candidates'):
        print c
        print c.text.split()

        # TODO:
        # - Look up the metric / field name in the rappor vars
        # - Concat the files
        # - Shell out to another tool that takes the params, and produces a map
        # file


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
