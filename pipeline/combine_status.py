#!/usr/bin/python
"""Summarize the results of many RAPPOR analysis runs.

Takes a list of STATUS.txt files on stdin, and reads the corresponding spec.txt
and log.txt files.  Writes a CSV to stdout.  Row key is (metric, date).
"""

import collections
import csv
import json
import os
import re
import sys


# Parse bash 'time' output:
# real    0m11.578s

# TODO: Parse the time from metrics.json instead.
TIMING_RE = re.compile(
    r'real \s+ (\d+) m ([\d.]+) s', re.VERBOSE)

# TODO: Could have decode-dist and decode-assoc output the PID?
PID_RE = re.compile(
    r'write_pid.py: PID (\d+)')  # not VERBOSE, spaces are literal


def ParseMemCsv(f):
  """Compute summary stats for memory.

  vm5_peak_kib -> max(vm_peak_kib)  # over 5 second intervals.  Since it uses
  the kernel, it's accurate except for takes that spike in their last 4
  seconds.

  vm5_mean_kib -> mean(vm_size_kib)  # over 5 second intervals
  """
  peak_by_pid = collections.defaultdict(list)
  size_by_pid = collections.defaultdict(list)

  # Parse columns we care about, by PID
  c = csv.reader(f)
  for i, row in enumerate(c):
    if i == 0:
      continue  # skip header
    # looks like timestamp, pid, then (rss, peak, size)
    _, pid, _, peak, size = row
    if peak != '':
      peak_by_pid[pid].append(int(peak))
    if size != '':
      size_by_pid[pid].append(int(size))

  mem_by_pid = {}

  # Now compute summaries
  pids = peak_by_pid.keys()
  for pid in pids:
    peaks = peak_by_pid[pid]
    vm5_peak_kib = max(peaks)

    sizes = size_by_pid[pid]
    vm5_mean_kib = sum(sizes) / len(sizes)

    mem_by_pid[pid] = (vm5_peak_kib, vm5_mean_kib)

  return mem_by_pid


def CheckJobId(job_id, parts):
  """Sanity check for date or smoke test."""
  if not job_id.startswith('201') and not job_id.startswith('smoke'):
    raise RuntimeError(
        "Expected job ID to start with '201' or 'smoke': got %r (%s)" %
        (job_id, parts))


def ReadStatus(f):
  status_line = f.readline().strip()
  return status_line.split()[0]  # OK, TIMEOUT, FAIL


def CombineDistTaskStatus(stdin, c_out, mem_by_pid):
  """Read status task paths from stdin, write CSV summary to c_out'."""

  #util.log('%s', mem_by_pid)

  # Parses:
  # - input path for metric name and date
  # - spec.txt for task params
  # - STATUS.txt for task success/failure
  # - metrics.json for output metrics
  # - log.txt for timing, if it ran to completion
  #   - and for structured data
  # - join with mem by PID

  header = (
      'job_id', 'params_file', 'map_file',
      'metric', 'date',
      'vm5_peak_kib', 'vm5_mean_kib',  # set when not skipped
      'seconds', 'status',
      # only set when OK
      'num_reports', 'num_rappor', 'allocated_mass',
      # only set when failed
      'fail_reason')
  c_out.writerow(header)

  for line in stdin:
    #
    # Receive a STATUS.txt path on each line of stdin, and parse it.
    #
    status_path = line.strip()

    with open(status_path) as f:
      status = ReadStatus(f)

    # Path should look like this:
    # ~/rappor/cron/2015-05-20__19-22-01/raw/Settings.NewTabPage/2015-05-19/STATUS.txt
    parts = status_path.split('/')
    job_id = parts[-5]
    CheckJobId(job_id, parts)

    #
    # Parse the job spec
    #
    result_dir = os.path.dirname(status_path)
    spec_file = os.path.join(result_dir, 'spec.txt')
    with open(spec_file) as f:
      spec_line = f.readline()
      # See backfill.sh analyze-one for the order of these 7 fields.
      # There are 3 job constants on the front.
      (num_reports, metric_name, date, counts_path, params_path,
       map_path, _) = spec_line.split()

    # NOTE: These are all constant per metric.  Could have another CSV and
    # join.  But denormalizing is OK for now.
    params_file = os.path.basename(params_path)
    map_file = os.path.basename(map_path)

    # remove extension
    params_file, _ = os.path.splitext(params_file)
    map_file, _ = os.path.splitext(map_file)

    #
    # Read the log
    #
    log_file = os.path.join(result_dir, 'log.txt')
    with open(log_file) as f:
      lines = f.readlines()

    # Search lines in reverse order for total time.  It could have output from
    # multiple 'time' statements, and we want the last one.
    seconds = None  # for skipped
    for i in xrange(len(lines) - 1, -1, -1):
      # TODO: Parse the R timing too.  Could use LOG_RECORD_RE.
      m = TIMING_RE.search(lines[i])
      if m:
        min_part, sec_part = m.groups()
        seconds = float(min_part) * 60 + float(sec_part)
        break

    # Extract stack trace
    if status == 'FAIL':
      # Stack trace looks like: "Calls: main -> RunOne ..."
      fail_reason = ''.join(line.strip() for line in lines if 'Calls' in line)
    else:
      fail_reason = None

    # Extract PID and join with memory results
    pid = None
    vm5_peak_kib = None
    vm5_mean_kib = None
    if mem_by_pid:
      for line in lines:
        m = PID_RE.match(line)
        if m:
          pid = m.group(1)
          # Could the PID not exist if the process was super short was less
          # than 5 seconds?
          try:
            vm5_peak_kib, vm5_mean_kib = mem_by_pid[pid]
          except KeyError:  # sometimes we don't add mem-track on the front
            vm5_peak_kib, vm5_mean_kib = None, None
          break
    else:
      pass  # we weren't passed memory.csv

    #
    # Read the metrics
    #
    metrics = {}
    metrics_file = os.path.join(result_dir, 'metrics.json')
    if os.path.isfile(metrics_file):
      with open(metrics_file) as f:
        metrics = json.load(f)

    num_rappor = metrics.get('num_detected')
    allocated_mass = metrics.get('allocated_mass')

    # Construct and write row
    row = (
        job_id, params_file, map_file,
        metric_name, date,
        vm5_peak_kib, vm5_mean_kib,
        seconds, status,
        num_reports, num_rappor, allocated_mass,
        fail_reason)

    c_out.writerow(row)


def CombineAssocTaskStatus(stdin, c_out):
  """Read status task paths from stdin, write CSV summary to c_out'."""

  header = (
      'job_id', 'metric', 'date', 'status', 'num_reports',
      'total_elapsed_seconds', 'em_elapsed_seconds', 'var1', 'var2', 'd1',
      'd2')

  c_out.writerow(header)

  for line in stdin:
    status_path = line.strip()

    with open(status_path) as f:
      status = ReadStatus(f)

    parts = status_path.split('/')
    job_id = parts[-6]
    CheckJobId(job_id, parts)

    #
    # Parse the job spec
    #
    result_dir = os.path.dirname(status_path)
    spec_file = os.path.join(result_dir, 'assoc-spec.txt')
    with open(spec_file) as f:
      spec_line = f.readline()
      # See backfill.sh analyze-one for the order of these 7 fields.
      # There are 3 job constants on the front.

      # 5 job params
      (_, _, _, _, _,
       dummy_num_reports, metric_name, date, reports, var1, var2, map1,
       output_dir) = spec_line.split()

    #
    # Parse decode-assoc metrics
    #
    metrics = {}
    metrics_file = os.path.join(result_dir, 'assoc-metrics.json')
    if os.path.isfile(metrics_file):
      with open(metrics_file) as f:
        metrics = json.load(f)

    # After we run it we have the actual number of reports
    num_reports = metrics.get('num_reports')
    total_elapsed_seconds = metrics.get('total_elapsed_time')
    em_elapsed_seconds = metrics.get('em_elapsed_time')
    estimate_dimensions = metrics.get('estimate_dimensions')
    if estimate_dimensions:
      d1, d2 = estimate_dimensions
    else:
      d1, d2 = (0, 0)  # unknown

    row = (
        job_id, metric_name, date, status, num_reports, total_elapsed_seconds,
        em_elapsed_seconds, var1, var2, d1, d2)
    c_out.writerow(row)


def main(argv):
  action = argv[1]

  try:
    mem_csv = argv[2]
  except IndexError:
    mem_by_pid = None
  else:
    with open(mem_csv) as f:
      mem_by_pid = ParseMemCsv(f)

  if action == 'dist':
    c_out = csv.writer(sys.stdout)
    CombineDistTaskStatus(sys.stdin, c_out, mem_by_pid)

  elif action == 'assoc':
    c_out = csv.writer(sys.stdout)
    CombineAssocTaskStatus(sys.stdin, c_out)

  else:
    raise RuntimeError('Invalid action %r' % action)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
