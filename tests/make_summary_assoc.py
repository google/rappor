#!/usr/bin/python
"""Given a regtest result tree, prints an HTML summary on stdout.

See HTML skeleton in tests/assoctest.html.
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

  <!-- RAPPOR params -->
  <td></td>
  <td></td>
  <td></td>
  <td></td>
  <td></td>
  <td></td>

  <!-- Result metrics -->
  <td></td>
  <td></td>
  <td></td>
  <td>%(mean_chisqdiff)s</td>
  <td>%(mean_l1d)s</td>
  <td>%(mean_rtime)s</td>
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

  spec_in_html = ' '.join('<td>%s</td>' % cell for cell in spec_row[3:])

  return spec_in_html


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


def ParseMetrics(metrics_file, log_file):
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

  (td_chisq, ed_chisq, l1d, rtime, d1, d2) = metrics_row

  td_chisq = float(td_chisq)
  ed_chisq = float(ed_chisq)

  l1d = float(l1d)
  rtime = float(rtime)

  elapsed_time = ExtractTime(log_file)

  metrics_row_str = [
    '%s' % d1,
    '%s' % d2,
    '%.3f' % td_chisq,
    '%.3f' % ed_chisq,
    '%.3f' % l1d,
    str(rtime),
  ]

  metrics_row_dict = {
    'd1': [d1],
    'd2': [d2],
    'l1d': [l1d],
    'rtime': [rtime],
    'chisqdiff': [abs(td_chisq - ed_chisq)],
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
      'mean_l1d': FormatMeanWithSem(means_with_sem['l1d'], percent=False),
      'mean_chisqdiff': FormatMeanWithSem(means_with_sem['chisqdiff'], percent=False),
      'mean_rtime': FormatMeanWithSem(means_with_sem['rtime']),
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
      'l1d': {},  # l1 distance
      'chisqdiff': {}, # abs diff in values for the chisq test between true
                       # distr and estimated distr.
      'rtime': {},  # R run time
  }

  # If there are too many tests, the plots are not included in the results
  # file. Instead, rows' names are links to the corresponding .png files.
  include_plots = len(test_instances) < 20
  include_plots = False

  for instance in test_instances:
    # A test instance is idenfied by the test name and the test run.
    test_case, test_instance = instance.split(' ')

    spec_file = os.path.join(base_dir, test_case, 'spec.txt')
    if not os.path.isfile(spec_file):
      raise RuntimeError('{} is missing'.format(spec_file))

    spec_html = ParseSpecFile(spec_file)
    metrics_html = ''  # will be filled in later on, if metrics exist

    report_dir = os.path.join(base_dir, test_case, test_instance + '_report')

    metrics_file = os.path.join(report_dir, 'metrics.csv')
    log_file = os.path.join(report_dir, 'log.txt')
    plot_file = os.path.join(report_dir, 'dist.png')

    cell1_html = FormatCell1(test_case, test_instance, metrics_file, log_file,
                             plot_file, include_plots)

    if os.path.isfile(metrics_file):
      # ParseMetrics outputs an HTML table row and also updates lists
      metrics_dict, metrics_html = ParseMetrics(metrics_file, log_file)

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
