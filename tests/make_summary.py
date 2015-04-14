#!/usr/bin/python
"""Given a regtest result tree, prints an HTML summary on stdout.

See HTML skeleton in tests/regtest.html.
"""

import os
import re
import sys


# Simulation parameters and result metrics.
EMPTY_ROW = """\
<tr>
  <td>
    %(name)s
  </td>
  <td colspan = 3>
  missing
  </td>
</tr>
"""

SUMMARY_ROW = """\
<tfoot style="font-weight: bold; text-align: right">
<tr>
  <td>
    %(name)s
  </td>

  <!-- input params -->
  <td></td>
  <td></td>
  <td></td>
  <td></td>

  <!-- RAPPOR params -->
  <td></td>
  <td></td>
  <td></td>
  <td></td>
  <td></td>
  <td></td>

  <!-- MAP params -->
  <td></td>
  <td></td>

  <!-- Result metrics -->
  <td></td>
  <td></td>
  <td>%(mean_fpr)s</td>
  <td>%(mean_fnr)s</td>
  <td>%(mean_tv)s</td>
  <td>%(mean_am)s</td>
  <td>%(mean_time)s</td>
</tr>
</tfoot>
"""

# Navigation and links to plot.
DETAILS = """\
<p style="text-align: right">
  <a href="#top">Up</a>
</p>

<a id="%(anchor)s"></a>

<p style="text-align: center">
  <img src="%(instance_dir)s/dist.png"/>
</p>

<p>
<a href="%(instance_dir)s">%(name)s files</a>
</p>
"""


def FormatFloat(x, percent):
  """Formats a floating-point number."""
  if percent:
    return '{:.1f}%'.format(x * 100.0)
  else:
    return '{:.3f}'.format(x)


def FormatEstimate(m_std_error, percent=False):
  """Formats an estimate with standard error."""
  if m_std_error is None:
    return ""
  m, std_error = m_std_error
  if std_error is None:
    return FormatFloat(m, percent)
  else:
    return '{}&plusmn;{}'.format(
        FormatFloat(m, percent),
        FormatFloat(std_error, percent))


def Mean(l):
  """Computes the mean (average) for a list of numbers."""
  if l:
    return float(sum(l)) / len(l)


def SampleVar(l):
  """Computes the sample variance for a list of numbers."""
  if len(l) > 1:
    mean = Mean(l)
    var = sum([(x - mean)**2 for x in l]) / (len(l) - 1)
    return var


def StandardErrorEstimate(l):
  """Returns the standard error estimate for a list of numbers.

  For a singleton the standard error is assumed to be 10% of its value.
  """
  if len(l) > 1:
    return (SampleVar(l) / len(l))**.5
  elif l:
    return l[0] / 10.0


def WeightedAverageOfAverages(list_of_lists, cap):
  """Computes the average of averages, weighted by accuracy.

  Given a list of lists of numbers, computes a weighted average of averages
  together the standard error of the estimate. Contribution from each list is
  weighted proportionally to the standard error of its sample mean.
  (Sublists with lower accuracy contribute less to the total). The cap limits
  the weight of any one's list.
  Args:
    list_of_list: A list of list of floats.
    cap:  Limit on any list's weight
  Returns:
    A pair of floats - average and its standard error.
  """
  l = [sublist for sublist in list_of_lists if sublist]
  if not l:
    return None

  total = 0
  total_weights = 0
  total_sem = 0  # SEM - Standard Error of the Mean

  for sublist in l:
    std_error = StandardErrorEstimate(sublist)
    weight = 1 / std_error if std_error > 1.0 / cap else cap

    total += Mean(sublist) * weight
    total_weights += weight
    total_sem += std_error**2 * weight**2  # == 1 when the weight is < cap

  std_error_estimate = total_sem**.5 / total_weights

  return total / total_weights, std_error_estimate


def AverageOfAverages(list_of_lists):
  """Returns the average of averages with the standard error of the estimate.
  """
  means = [Mean(l) for l in list_of_lists if l]
  if means:
    # Compute variances of the estimate for each sublist.
    se = [StandardErrorEstimate(l)**2 for l in list_of_lists if l]

    return (Mean(means),  # Mean over all sublists
            sum(se)**.5 / len(se))  # Standard deviation of the mean


def ParseSpecFile(spec_filename):
  """Parses the spec (parameters) file.

  Returns:
    An integer and a string. The integer is the number of bogus candidates
    and the string is parameters in the HTML format.
  """
  with open(spec_filename) as s:
    spec_row = s.readline().split()

  spec_row.pop(1)  # drop the run_id (must be 1 if correctly generated)

  # Second to last column is 'num_additional' -- the number of bogus
  # candidates added
  num_additional = int(spec_row[-2])

  spec_in_html = ' '.join('<td>%s</td>' % cell for cell in spec_row[1:])

  return num_additional, spec_in_html


def ParseLogFile(log_filename):
  """Extracts the elapsed time information from the log file.

  Returns:
     A float or None in case of failure.
  """
  if os.path.isfile(log_filename):
    with open(log_filename) as log:
      log_str = log.read()
    match = re.search(r'took ([0-9.]+) seconds', log_str)
    if match:
      return float(match.group(1))


def ParseMetrics(report_dir, num_additional, metrics_lists):
  """Processes the metrics file.

  Args:
    report_dir: A directory name containing metrics.csv and log.txt.
    num_additional: A number of bogus candidates added to the candidate list.
    metrics_lists: A dictionary containing lists (one for each metric) of
        lists (one for each test case) of metrics (one for each test run).
  Returns:
    Part of the report row formatted in HTML. metrics_lists is updated with
    new metrics.
  """
  metrics_filename = os.path.join(report_dir, 'metrics.csv')

  with open(metrics_filename) as m:
    m.readline()
    metrics_row = m.readline().split(',')

  # Format numbers and sum
  (num_actual, num_rappor, num_false_pos, num_false_neg, total_variation,
   allocated_mass) = metrics_row

  num_actual = int(num_actual)
  num_rappor = int(num_rappor)

  num_false_pos = int(num_false_pos)
  num_false_neg = int(num_false_neg)

  total_variation = float(total_variation)
  allocated_mass = float(allocated_mass)

  log_filename = os.path.join(report_dir, 'log.txt')
  elapsed_time = ParseLogFile(log_filename)

  # e.g. if there are 20 additional candidates added, and 1 false positive,
  # the false positive rate is 5%.
  fp_rate = float(num_false_pos) / num_additional if num_additional else 0
  # e.g. if there are 100 strings in the true input, and 80 strings
  # detected by RAPPOR, then we have 20 false negatives, and a false
  # negative rate of 20%.
  fn_rate = float(num_false_neg) / num_actual

  metrics_row_str = [
      str(num_actual),
      str(num_rappor),
      '%.1f%% (%d)' % (fp_rate * 100, num_false_pos) 
          if num_additional else '',
      '%.1f%% (%d)' % (fn_rate * 100, num_false_neg),
      '%.3f' % total_variation,
      '%.3f' % allocated_mass,
      '%.2f' % elapsed_time if elapsed_time is not None else '',
  ]

  if num_additional:
    metrics_lists['fpr'][-1].append(fp_rate)
  metrics_lists['fnr'][-1].append(fn_rate)
  metrics_lists['tv'][-1].append(total_variation)
  metrics_lists['am'][-1].append(allocated_mass)
  if elapsed_time is not None:
    metrics_lists['time'][-1].append(elapsed_time)

  # return metrics formatted as HTML table entries
  return ' '.join('<td>%s</td>' % cell for cell in metrics_row_str)


def FormatRowName(case_name, run_id_str, metrics_name, link_to_plots):
  """Outputs an HTML table entry.
  """
  relpath_report = '{}/{}_report'.format(case_name, run_id_str)
  if os.path.isfile(metrics_name):
    if link_to_plots:
      link = '#' + case_name + '_' + run_id_str  # anchor
    else:
      link = relpath_report + '/' + 'dist.png'
  else:  # no results likely due to an error, puts a link to the log file
    link = relpath_report + '/' + 'log.txt'

  return '<td><a href="{}">{}</a></td>'.format(link, case_name)


def FormatSummaryRows(metrics_lists):
  """Outputs an HTML-formatted summary row.
  """
  means_with_sem = {}  # SEM - standard error of the mean

  for key in metrics_lists:
    means_with_sem[key] = AverageOfAverages(metrics_lists[key])
    # If none of the lists is longer than one element, drop the SEM component.
    if means_with_sem[key] and max([len(l) for l in metrics_lists[key]]) < 2:
      means_with_sem[key] = [means_with_sem[key][0], None]

  summary = {
      'name': 'Means',
      'mean_fpr': FormatEstimate(means_with_sem['fpr'], percent=True),
      'mean_fnr': FormatEstimate(means_with_sem['fnr'], percent=True),
      'mean_tv': FormatEstimate(means_with_sem['tv'], percent=True),
      'mean_am': FormatEstimate(means_with_sem['am'], percent=True),
      'mean_time': FormatEstimate(means_with_sem['time']),
  }
  return SUMMARY_ROW % summary


def FormatPlots(base_dir, test_instances):
  """Outputs HTML-formatted plots.
  """
  result = ''
  for instance in test_instances:
    # A test instance is idenfied by the test name and the test run.
    case_name, run_id_str = instance.split(' ')
    instance_dir = case_name + '/' + run_id_str + '_report'
    if os.path.isfile(os.path.join(base_dir, instance_dir, 'dist.png')):
      result += DETAILS % {'anchor': case_name + '_' + run_id_str,
                           'name': '{} (instance {})'.format(case_name,
                                                             run_id_str),
                           'instance_dir': instance_dir}
  return result


def main(argv):
  base_dir = argv[1]

  # This file has the test case names, in the order that they should be
  # displayed.
  path = os.path.join(base_dir, 'test-cases.txt')
  with open(path) as f:
    test_instances = [line.strip() for line in f]

  metrics_lists = {
      'tv': [],  # total_variation for all test cases
      'fpr': [],  # list of false positive rates
      'fnr': [],  # list of false negative rates
      'am': [],  # list of total allocated masses
      'time': [],  # list of total elapsed time measurements
  }

  # If there are too many tests, the plots are not included in the results
  # file. Instead, rows' names are links to the corresponding .png files.
  include_plots = len(test_instances) < 20

  for instance in test_instances:
    # A test instance is idenfied by the test name and the test run.
    case_name, run_id_str = instance.split(' ')
    # if this is the first run of a test case, start anew
    if run_id_str == '1':
      for metric in metrics_lists:
        metrics_lists[metric].append([])

    spec = os.path.join(base_dir, case_name, 'spec.txt')
    if os.path.isfile(spec):
      num_additional, row_spec = ParseSpecFile(spec)

      report_dir = os.path.join(base_dir, case_name, run_id_str + '_report')
      if os.path.isdir(report_dir):
        metrics = os.path.join(report_dir, 'metrics.csv')

        row_name = FormatRowName(case_name, run_id_str, metrics, include_plots)

        if os.path.isfile(metrics):
          # ParseMetrics outputs an HTML table row and also updates lists
          row_metrics = ParseMetrics(report_dir, num_additional, metrics_lists)
        else:
          row_metrics = ''
      else:
        row_name = '<td>{}<td>'.format(case_name)
        row_metrics = ''

      print '<tr>{}{}{}</tr>'.format(row_name, row_spec, row_metrics)
    else:
      print EMPTY_ROW % {'name': case_name}

  print FormatSummaryRows(metrics_lists)

  print '</tbody>'
  print '</table>'
  print '<p style="padding-bottom: 3em"></p>'  # vertical space

  # Plot links.
  if include_plots:
    print FormatPlots(base_dir, test_instances)
  else:
    print '<p>Too many tests to include plots.\
           Click links within rows for details.</p>'


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
