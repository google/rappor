#!/usr/bin/python -S
"""
task_spec_test.py: Tests for task_spec.py
"""

import cStringIO
import unittest

import task_spec  # module under test


class TaskSpecTest(unittest.TestCase):

  def testCountReports(self):
    f = cStringIO.StringIO("""\
1,2
3,4
5,6
""")
    c = task_spec.CountReports(f)
    self.assertEqual(9, c)

  def testDist(self):
    # NOTE: These files are opened, in order to count the reports.  Maybe skip
    # that step.
    f = cStringIO.StringIO("""\
_tmp/counts/2015-12-01/exp_counts.csv
_tmp/counts/2015-12-01/gauss_counts.csv
_tmp/counts/2015-12-02/exp_counts.csv
_tmp/counts/2015-12-02/gauss_counts.csv
""")
    input_iter = task_spec.DistInputIter(f)
    #for row in input_iter:
    #  print row

    field_id_lookup = {}

    # var name -> map filename
    f = cStringIO.StringIO("""\
var,map_filename
exp,map.csv
unif,map.csv
gauss,map.csv
""")
    dist_maps = task_spec.DistMapLookup(f, '_tmp/maps')

    f2 = cStringIO.StringIO("""\
metric,var,var_type,params
exp,,string,params
unif,,string,params
gauss,,string,params
""")
    var_schema = task_spec.VarSchema(f2, '_tmp/config')

    for row in task_spec.DistTaskSpec(
        input_iter, field_id_lookup, var_schema, dist_maps, None):
      print row


if __name__ == '__main__':
  unittest.main()
