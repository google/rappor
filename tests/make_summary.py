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

    # first cell is test case name, which we already have
    row = spec_row[1:] + metrics_row
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
