#!/usr/bin/python
"""Given a regtest result tree, prints an HTML summary on stdout.

See HTML skeleton in tests/regtest.html.
"""

import os
import sys


# Simulation parameters and result metrics.
ROW = """\
<tr>
  <td>
    <a href="#%(name)s">%(name)s</a>
  </td>
  %(cell_html)s
</tr>
"""

# Navigation and links to plot.
DETAILS = """\
<p style="text-align: right">
  <a href="#top">Up</a>
</p>

<a id="%(name)s"></a>

<p style="text-align: center">
  <img src="%(name)s_report/dist.png" />
</p>

<p>
<a href="%(name)s">%(name)s files</a>
</p>
"""


def Percent(n, d):
  """Given numerator and denominator, return a percent string."""
  return '%.1f%% (%d)' % (float(n) * 100 / d, n)


def main(argv):
  base_dir = argv[1]

  # This file has the test case names, in the order that they should be
  # displayed.
  path = os.path.join(base_dir, 'test-cases.txt')
  with open(path) as f:
    test_cases = [line.strip() for line in f]

  for case in test_cases:
    spec = os.path.join(base_dir, case, 'spec.txt')
    with open(spec) as s:
      spec_row = s.readline().split()

    metrics = os.path.join(base_dir, case + '_report', 'metrics.csv')
    with open(metrics) as m:
      header = m.readline()
      metrics_row = m.readline().split(',')

    # Format numbers and sum
    (num_actual, num_rappor, num_false_pos, num_false_neg, total_variation,
     sum_proportion) = metrics_row

    num_actual = int(num_actual)
    num_rappor = int(num_rappor)

    num_false_pos = int(num_false_pos)
    num_false_neg = int(num_false_neg)

    total_variation = float(total_variation)
    sum_proportion = float(sum_proportion)

    metrics_row_str = [
        str(num_actual),
        str(num_rappor),
        Percent(num_false_pos, num_actual),
        Percent(num_false_neg, num_actual),
        '%.3f' % total_variation,
        '%.3f' % sum_proportion,
        ]

    # first cell is test case name, which we already have
    row = spec_row[1:] + metrics_row_str
    cell_html = ' '.join('<td>%s</td>' % cell for cell in row)

    data = {
        # See tests/regtest_spec.py for the definition of the spec row
        'name': case,
        'cell_html': cell_html,
    }
    print ROW % data

  print '</tbody>'
  print '</table>'
  print '<p style="padding-bottom: 3em"></p>'  # vertical space

  # Plot links.
  # TODO: Add params?
  for case in test_cases:
    print DETAILS % {'name': case}


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
