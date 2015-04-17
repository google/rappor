#!/usr/bin/python
"""Given a regtest result tree, prints an HTML summary on stdout.

See HTML skeleton in tests/regtest.html.
"""

import os
import re
import sys


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


def FormatMeanWithSem(m_std_error, percent=False):
  """Formats an estimate with standard error."""
  if m_std_error is None:
    return ''
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
  else:
    return None


def SampleVar(l):
  """Computes the sample variance for a list of numbers."""
  if len(l) > 1:
    mean = Mean(l)
    var = sum([(x - mean) ** 2 for x in l]) / (len(l) - 1)
    return var
  else:
    return None


def StandardErrorEstimate(l):
  """Returns the standard error estimate for a list of numbers.

  For a singleton the standard error is assumed to be 10% of its value.
  """
  if len(l) > 1:
    return (SampleVar(l) / len(l)) ** .5
  elif l:
    return l[0] / 10.0
  else:
    return None


def MeanOfMeans(dict_of_lists):
  """Returns the average of averages with the standard error of the estimate.
  """
  means = [Mean(dict_of_lists[key]) for key in dict_of_lists
           if dict_of_lists[key]]
  if means:
    # Compute variances of the estimate for each sublist.
    se = [StandardErrorEstimate(dict_of_lists[key]) ** 2 for key
          in dict_of_lists if dict_of_lists[key]]
    return (Mean(means),  # Mean over all sublists
            sum(se) ** .5 / len(se))  # Standard deviation of the mean
  else:
    return None


def ParseSpecFile(spec_filename):
  """Parses the spec (parameters) file.

  Returns:
    An integer and a string. The integer is the number of bogus candidates
    and the string is parameters in the HTML format.
  """
  with open(spec_filename) as s:
    spec_row = s.readline().split()

  # Second to last column is 'num_additional' -- the number of bogus
  # candidates added
  num_additional = int(spec_row[-2])

  spec_in_html = ' '.join('<td>%s</td>' % cell for cell in spec_row[1:])

  return num_additional, spec_in_html


def ExtractTime(log_filename):
  """Extracts the elapsed time information from the log file.

  Returns:
     Elapsed time (in seconds) or None in case of failure.
  """
  if os.path.isfile(log_filename):
    with open(log_filename) as log:
      log_str = log.read()
    # Matching a line output by analyze.R.
    match = re.search(r'Inference took ([0-9.]+) seconds', log_str)
    if match:
      return float(match.group(1))
  return None


def ParseMetrics(metrics_file, log_file, num_additional):
  """Processes the metrics file.

  Args:
    report_dir: A directory name containing metrics.csv and log.txt.
    num_additional: A number of bogus candidates added to the candidate list.

  Returns a pair:
    - A dictionary of metrics (some can be []).
    - An HTML-formatted portion of the report row.
  """
  with open(metrics_file) as m:
    m.readline()
    metrics_row = m.readline().split(',')

  (num_actual, num_rappor, num_false_pos, num_false_neg, total_variation,
   allocated_mass) = metrics_row

  num_actual = int(num_actual)
  num_rappor = int(num_rappor)

  num_false_pos = int(num_false_pos)
  num_false_neg = int(num_false_neg)

  total_variation = float(total_variation)
  allocated_mass = float(allocated_mass)

  elapsed_time = ExtractTime(log_file)

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
      '%.1f%% (%d)' % (fp_rate * 100, num_false_pos) if num_additional else '',
      '%.1f%% (%d)' % (fn_rate * 100, num_false_neg),
      '%.3f' % total_variation,
      '%.3f' % allocated_mass,
      '%.2f' % elapsed_time if elapsed_time is not None else '',
  ]

  metrics_row_dict = {
      'tv': [total_variation],
      'fpr': [fp_rate] if num_additional else [],
      'fnr': [fn_rate],
      'am': [allocated_mass],
      'time': [elapsed_time] if elapsed_time is not None else [],
  }

  # return metrics formatted as HTML table entries
  return (metrics_row_dict,
          ' '.join('<td>%s</td>' % cell for cell in metrics_row_str))


def FormatCell1(test_case, test_instance, metrics_file, log_file, plot_file,
                link_to_plots):
  """Outputs an HTML table entry for the first cell of the row.

  The row is filled if the metrics file exist. The first cell contains a link
  that for short tables points to a plot file inline, for large tables to an
  external file.

  If the metrics file is missing, the link points to the log file (if one
  exists)
  """
  relpath_report = '{}/{}_report'.format(test_case, test_instance)
  if os.path.isfile(metrics_file):
    external_file = plot_file
    if link_to_plots:
      link = '#{}_{}'.format(test_case, test_instance)  # anchor
    else:
      link = os.path.join(relpath_report, 'dist.png')
  else:  # no results likely due to an error, puts a link to the log file
    external_file = log_file
    link = os.path.join(relpath_report, 'log.txt')

  if os.path.isfile(external_file):
    return '<td><a href="{}">{}</a></td>'.format(link, test_case)
  else:  # if no file to link to
    return '<td>{}</td>'.format(test_case)


def FormatSummaryRow(metrics_lists):
  """Outputs an HTML-formatted summary row."""
  means_with_sem = {}  # SEM - standard error of the mean

  for key in metrics_lists:
    means_with_sem[key] = MeanOfMeans(metrics_lists[key])
    # If none of the lists is longer than one element, drop the SEM component.
    if means_with_sem[key] and max([len(l) for l in metrics_lists[key]]) < 2:
      means_with_sem[key] = [means_with_sem[key][0], None]

  summary = {
      'name': 'Means',
      'mean_fpr': FormatMeanWithSem(means_with_sem['fpr'], percent=True),
      'mean_fnr': FormatMeanWithSem(means_with_sem['fnr'], percent=True),
      'mean_tv': FormatMeanWithSem(means_with_sem['tv'], percent=True),
      'mean_am': FormatMeanWithSem(means_with_sem['am'], percent=True),
      'mean_time': FormatMeanWithSem(means_with_sem['time']),
  }
  return SUMMARY_ROW % summary


def FormatPlots(base_dir, test_instances):
  """Outputs HTML-formatted plots."""
  result = ''
  for instance in test_instances:
    # A test instance is identified by the test name and the test run.
    test_case, test_instance, _ = instance.split(' ')
    instance_dir = test_case + '/' + test_instance + '_report'
    if os.path.isfile(os.path.join(base_dir, instance_dir, 'dist.png')):
      result += DETAILS % {'anchor': test_case + '_' + test_instance,
                           'name': '{} (instance {})'.format(test_case,
                                                             test_instance),
                           'instance_dir': instance_dir}
  return result


def main(argv):
  base_dir = argv[1]

  # This file has the test case names, in the order that they should be
  # displayed.
  path = os.path.join(base_dir, 'test-instances.txt')
  with open(path) as f:
    test_instances = [line.strip() for line in f]

  # Metrics are assembled into a dictionary of dictionaries. The top-level
  # key is the metric name ('tv', 'fpr', etc.), the second level key is
  # the test case. These keys reference a list of floats, which can be empty.
  metrics = {
      'tv': {},  # total_variation for all test cases
      'fpr': {},  # dictionary of false positive rates
      'fnr': {},  # dictionary of false negative rates
      'am': {},  # dictionary of total allocated masses
      'time': {},  # dictionary of total elapsed time measurements
  }

  # If there are too many tests, the plots are not included in the results
  # file. Instead, rows' names are links to the corresponding .png files.
  include_plots = len(test_instances) < 20

  for instance in test_instances:
    # A test instance is idenfied by the test name and the test run.
    test_case, test_instance, _ = instance.split(' ')

    spec_file = os.path.join(base_dir, test_case, 'spec.txt')
    if not os.path.isfile(spec_file):
      raise RuntimeError('{} is missing'.format(spec_file))

    num_additional, spec_html = ParseSpecFile(spec_file)
    metrics_html = ''  # will be filled in later on, if metrics exist

    report_dir = os.path.join(base_dir, test_case, test_instance + '_report')

    metrics_file = os.path.join(report_dir, 'metrics.csv')
    log_file = os.path.join(report_dir, 'log.txt')
    plot_file = os.path.join(report_dir, 'dist.png')

    cell1_html = FormatCell1(test_case, test_instance, metrics_file, log_file,
                             plot_file, include_plots)

    if os.path.isfile(metrics_file):
      # ParseMetrics outputs an HTML table row and also updates lists
      metrics_dict, metrics_html = ParseMetrics(metrics_file, log_file,
                                                num_additional)

      # Update the metrics structure. Initialize dictionaries if necessary.
      for m in metrics:
        if not test_case in metrics[m]:
          metrics[m][test_case] = metrics_dict[m]
        else:
          metrics[m][test_case] += metrics_dict[m]

    print '<tr>{}{}{}</tr>'.format(cell1_html, spec_html, metrics_html)

  print FormatSummaryRow(metrics)

  print '</tbody>'
  print '</table>'
  print '<p style="padding-bottom: 3em"></p>'  # vertical space

  # Plot links.
  if include_plots:
    print FormatPlots(base_dir, test_instances)
  else:
    print ('<p>Too many tests to include plots. '
           'Click links within rows for details.</p>')


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
