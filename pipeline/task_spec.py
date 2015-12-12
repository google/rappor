#!/usr/bin/python
"""Read a list of 'counts' paths on stdin, and write a task spec on stdout.

Each line represents a task, or R process invocation.  The params on each line
are passed to ./dist.sh decode-many or ./assoc.sh decode-many.
"""

import collections
import csv
import errno
import optparse
import os
import pprint
import re
import sys

import util


def _ReadDistMaps(f):
  dist_maps = {}
  c = csv.reader(f)
  for i, row in enumerate(c):
    if i == 0:
      expected = ['var', 'map_filename']
      if row != expected:
        raise RuntimeError('Expected CSV header %s' % expected)
      continue  # skip header

    var_name, map_filename = row
    dist_maps[var_name] = map_filename
  return dist_maps


class DistMapLookup(object):
  """Create a dictionary of var -> map to analyze against.

  TODO: Support a LIST of maps.  Users should be able to specify more than one.
  """
  def __init__(self, f, map_dir):
    self.dist_maps = _ReadDistMaps(f)
    self.map_dir = map_dir

  def GetMapPath(self, var_name):
    filename = self.dist_maps[var_name]
    return os.path.join(self.map_dir, filename)


def CreateFieldIdLookup(f):
  """Create a dictionary that specifies single variable analysis each var.

  Args:
    config_dir: directory of metadata, output by update_rappor.par

  Returns:
    A dictionary from field ID -> full field name

  NOTE: Right now we're only doing single variable analysis for strings, so we
  don't have the "type".
  """
  field_id_lookup = {}
  c = csv.reader(f)
  for i, row in enumerate(c):
    if i == 0:
      expected = ['metric', 'field', 'field_type', 'params', 'field_id']
      if row != expected:
        raise RuntimeError('Expected CSV header %s' % expected)
      continue

    metric, field, field_type, _, field_id = row

    if field_type != 'string':
      continue

    # Paper over the difference between plain metrics (single variable) and
    # metrics with fields (multiple variables, for association analysis).
    if field:
      full_field_name = '%s.%s' % (metric, field)
    else:
      full_field_name = metric

    field_id_lookup[field_id] = full_field_name
  return field_id_lookup


def _ReadVarSchema(f):
  """Given the rappor-vars.csv file, return a list of metric/var/type."""
  # metric -> list of (variable name, type)
  assoc_metrics = collections.defaultdict(list)
  params_lookup = {}

  c = csv.reader(f)
  for i, row in enumerate(c):
    if i == 0:
      expected = ['metric', 'var', 'var_type', 'params']
      if row != expected:
        raise RuntimeError('Expected CSV header %s, got %s' % (expected, row))
      continue

    metric, var, var_type, params = row
    if var == '':
      full_var_name = metric
    else:
      full_var_name = '%s.%s' % (metric, var)
      # Also group multi-dimensional reports
      assoc_metrics[metric].append((var, var_type))

    params_lookup[full_var_name] = params

  return assoc_metrics, params_lookup


class VarSchema(object):
  """Object representing rappor-vars.csv.

  Right now we use it for slightly different purposes for dist and assoc
  analysis.
  """
  def __init__(self, f, params_dir):
    self.assoc_metrics, self.params_lookup = _ReadVarSchema(f)
    self.params_dir = params_dir

  def GetParamsPath(self, var_name):
    filename = self.params_lookup[var_name]
    return os.path.join(self.params_dir, filename + '.csv')

  def GetAssocMetrics(self):
    return self.assoc_metrics


def CountReports(f):
  num_reports = 0
  for line in f:
    first_col = line.split(',')[0]
    num_reports += int(first_col)
  return num_reports


DIST_INPUT_PATH_RE = re.compile(r'.*/(\d+-\d+-\d+)/(\S+)_counts.csv')


def DistInputIter(stdin):
  """Read lines from stdin and extract fields to construct analysis tasks."""
  for line in stdin:
    m = DIST_INPUT_PATH_RE.match(line)
    if not m:
      raise RuntimeError('Invalid path %r' % line)

    counts_path = line.strip()
    date, field_id = m.groups()

    yield counts_path, date, field_id


def DistTaskSpec(input_iter, field_id_lookup, var_schema, dist_maps, bad_c):
  """Print task spec for single variable RAPPOR to stdout."""

  num_bad = 0
  unique_ids = set()

  for counts_path, date, field_id in input_iter:
    unique_ids.add(field_id)

    # num_reports is used for filtering
    with open(counts_path) as f:
      num_reports = CountReports(f)

    # Look up field name from field ID
    if field_id_lookup:
      field_name = field_id_lookup.get(field_id)
      if field_name is None:
        # The metric id is the md5 hash of the name.  We can miss some, e.g. due
        # to debug builds.
        if bad_c:
          bad_c.writerow((date, field_id, num_reports))
          num_bad += 1
        continue
    else:
      field_name = field_id

    # NOTE: We could remove the params from the spec if decode_dist.R took the
    # --schema flag.  The var type is there too.
    params_path = var_schema.GetParamsPath(field_name)
    map_path= dist_maps.GetMapPath(field_name)

    yield num_reports, field_name, date, counts_path, params_path, map_path

  util.log('%d unique field IDs', len(unique_ids))
  if num_bad:
    util.log('Failed field ID -> field name lookup on %d files '
             '(check --field-ids file)', num_bad)


ASSOC_INPUT_PATH_RE = re.compile(r'.*/(\d+-\d+-\d+)/(\S+)_reports.csv')


def AssocInputIter(stdin):
  """Read lines from stdin and extract fields to construct analysis tasks."""
  for line in stdin:
    m = ASSOC_INPUT_PATH_RE.match(line)
    if not m:
      raise RuntimeError('Invalid path %r' % line)

    reports_path = line.strip()
    date, metric_name = m.groups()

    yield reports_path, date, metric_name


def CreateAssocVarPairs(rappor_metrics):
  """Yield a list of pairs of variables that should be associated.

  For now just do all (string x boolean) analysis.
  """
  var_pairs = collections.defaultdict(list)

  for metric, var_list in rappor_metrics.iteritems():
    string_vars = []
    boolean_vars = []

    # Separate variables into strings and booleans
    for var_name, var_type in var_list:
      if var_type == 'string':
        string_vars.append(var_name)
      elif var_type == 'boolean':
        boolean_vars.append(var_name)
      else:
        util.log('Unknown type variable type %r', var_type)

    for s in string_vars:
      for b in boolean_vars:
        var_pairs[metric].append((s, b))
  return var_pairs


# For debugging
def PrintAssocVarPairs(var_pairs):
  for metric, var_list in var_pairs.iteritems():
    print metric
    for var_name, var_type in var_list:
      print '\t', var_name, var_type


def AssocTaskSpec(input_iter, var_pairs, dist_maps, output_base_dir, bad_c):
  """Print the task spec for multiple variable RAPPOR to stdout."""
  # Flow:
  #
  # Long term: We should have assoc-analysis.xml, next to dist-analysis.xml?
  #
  # Short term: update_rappor.py should print every combination of string vs.
  # bool?  Or I guess we have it in rappor-vars.csv

  for reports_path, date, metric_name in input_iter:
    pairs = var_pairs[metric_name]
    for var1, var2 in pairs:
      # Assuming var1 is a string.  TODO: Use an assoc file, not dist_maps?
      field1_name = '%s.%s' % (metric_name, var1)
      map1_path = dist_maps.GetMapPath(field1_name)

      # e.g. domain_X_flags__DID_PROCEED
      # Don't use .. in filenames since it could be confusing.
      pair_name = '%s_X_%s' % (var1, var2.replace('..', '_'))
      output_dir = os.path.join(output_base_dir, metric_name, pair_name, date)

      yield metric_name, date, reports_path, var1, var2, map1_path, output_dir


def CreateOptionsParser():
  p = optparse.OptionParser()

  p.add_option(
      '--bad-report-out', dest='bad_report', metavar='PATH', type='str',
      default='',
      help='Optionally write a report of input filenames with invalid field '
           'IDs to this file.')
  p.add_option(
      '--config-dir', dest='config_dir', metavar='PATH', type='str',
      default='',
      help='Directory with metadata schema and params files to read.')
  p.add_option(
      '--map-dir', dest='map_dir', metavar='PATH', type='str',
      default='',
      help='Directory with map files to read.')
  p.add_option(
      '--output-base-dir', dest='output_base_dir', metavar='PATH', type='str',
      default='',
      help='Root of the directory tree where analysis output will be placed.')
  p.add_option(
      '--field-ids', dest='field_ids', metavar='PATH', type='str',
      default='',
      help='Optional CSV file with field IDs (generally should not be used).')

  return p


def main(argv):
  (opts, argv) = CreateOptionsParser().parse_args(argv)

  if opts.bad_report:
    bad_f = open(opts.bad_report, 'w')
    bad_c = csv.writer(bad_f)
  else:
    bad_c = None

  action = argv[1]

  if not opts.config_dir:
    raise RuntimeError('--config-dir is required')
  if not opts.map_dir:
    raise RuntimeError('--map-dir is required')
  if not opts.output_base_dir:
    raise RuntimeError('--output-base-dir is required')

  # This is shared between the two specs.
  path = os.path.join(opts.config_dir, 'dist-analysis.csv')
  with open(path) as f:
    dist_maps = DistMapLookup(f, opts.map_dir)

  path = os.path.join(opts.config_dir, 'rappor-vars.csv')
  with open(path) as f:
    var_schema = VarSchema(f, opts.config_dir)

  if action == 'dist':
    if opts.field_ids:
      with open(opts.field_ids) as f:
        field_id_lookup = CreateFieldIdLookup(f)
    else:
      field_id_lookup = {}

    input_iter = DistInputIter(sys.stdin)
    for row in DistTaskSpec(input_iter, field_id_lookup, var_schema, dist_maps,
                            bad_c):
      # The spec is a series of space-separated tokens.
      tokens = row + (opts.output_base_dir,)
      print ' '.join(str(t) for t in tokens)

  elif action == 'assoc':
    # Parse input
    input_iter = AssocInputIter(sys.stdin)

    # Create M x N association tasks
    var_pairs = CreateAssocVarPairs(var_schema.GetAssocMetrics())

    # Now add the other constant stuff
    for row in AssocTaskSpec(
        input_iter, var_pairs, dist_maps, opts.output_base_dir, bad_c):

      num_reports = 0  # placeholder, not filtering yet
      tokens = (num_reports,) + row
      print ' '.join(str(t) for t in tokens)

  else:
    raise RuntimeError('Invalid action %r' % action)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except IOError, e:
    if e.errno != errno.EPIPE:  # ignore broken pipe
      raise
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
