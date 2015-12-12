#!/usr/bin/Rscript
#
# Write an overview of task status, per-metric task status, task histograms.

library(data.table)
library(ggplot2)

options(stringsAsFactors = FALSE)  # get rid of annoying behavior

Log <- function(fmt, ...) {
  cat(sprintf(fmt, ...))
  cat('\n')
}

# max of non-NA values; NA if there are none
MaybeMax <- function(values) {
  v <- values[!is.na(values)]
  if (length(v) == 0) {
    m <- NA
  } else {
    m <- max(v)
  }
  as.numeric(m)  # data.table requires this; otherwise we get type errors
}

# mean of non-NA values; NA if there are none
MaybeMean <- function(values) {
  v <- values[!is.na(values)]
  if (length(v) == 0) {
    m <- NA
  } else {
    m <- mean(v)
  }
  as.numeric(m)  # data.table require this; otherwise we get type errors
}

WriteDistOverview <- function(summary, output_dir) {
  s <- data.table(summary)  # data.table syntax is easier here

  by_metric <-  s[ , list(
      params_file = unique(params_file),
      map_file = unique(map_file),
      days = length(date),
      max_num_reports = MaybeMax(num_reports),

      # summarize status
      ok = sum(status == 'OK'),
      fail = sum(status == 'FAIL'),
      timeout = sum(status == 'TIMEOUT'),
      skipped = sum(status == 'SKIPPED'),

      # TODO: Need to document the meaning of these metrics.
      # All could be NA
      # KiB -> MB
      #max_vm5_peak_mb = MaybeMax(vm5_peak_kib * 1024 / 1e6),
      #mean_vm5_mean_mb = MaybeMean(vm5_mean_kib * 1024 / 1e6),

      mean_secs = MaybeMean(seconds),
      mean_allocated_mass = MaybeMean(allocated_mass)

      # unique failure reasons
      # This can be used when there are different call stacks.
      #fail_reasons = length(unique(fail_reason[fail_reason != ""]))
      ), by=metric]

  # Case insensitive sort by metric name
  by_metric <- by_metric[order(tolower(by_metric$metric)), ]

  overview_path <- file.path(output_dir, 'overview.csv')
  write.csv(by_metric, file = overview_path, row.names = FALSE)
  Log("Wrote %s", overview_path)

  by_metric
}

WriteDistMetricStatus <- function(summary, output_dir) {
  # Write status.csv, num_reports.csv, and mass.csv for each metric.

  s <- data.table(summary)

  # loop over unique metrics, and write a CSV for each one
  for (m in unique(s$metric)) {
    # Select cols, and convert units.  Don't need params / map / metric.
    subframe <- s[s$metric == m,
                  list(job_id, date, status,
                       #vm5_peak_mb = vm5_peak_kib * 1024 / 1e6,
                       #vm5_mean_mb = vm5_mean_kib * 1024 / 1e6,
                       num_reports,
                       seconds,
                       allocated_mass, num_rappor)]

    # Sort by descending date.  Alphabetical sort works fine for YYYY-MM-DD.
    subframe <- subframe[order(subframe$date, decreasing = TRUE), ]

    out_path = file.path(output_dir, m, 'status.csv')
    write.csv(subframe, file = out_path, row.names = FALSE)
    Log("Wrote %s", out_path)
  }

  # This one is just for plotting with dygraphs.  TODO: can dygraphs do
  # something smarter?  Maybe you need to select the column in JavaScript, and
  # pass it an array, rather than CSV text.
  for (m in unique(s$metric)) {
    f1 <- s[s$metric == m, list(date, num_reports)]
    path1 <- file.path(output_dir, m, 'num_reports.csv')
    # NOTE: dygraphs (only in Firefox?) doesn't like the quotes around
    # "2015-04-03".  In general, we can't turn off quotes, because strings with
    # double quotes will be invalid CSV files.  But in this case, we only have
    # date and number columns, so we can.  dygraphs is mistaken here.
    write.csv(f1, file = path1, row.names = FALSE, quote = FALSE)
    Log("Wrote %s", path1)

    # Write unallocated mass.  TODO: Write the other 2 vars too?
    f2 <- s[s$metric == m,
            list(date,
                 unallocated_mass = 1.0 - allocated_mass)]

    path2 <- file.path(output_dir, m, 'mass.csv')
    write.csv(f2, file = path2, row.names = FALSE, quote = FALSE)
    Log("Wrote %s", path2)
  }
}

WritePlot <- function(p, outdir, filename, width = 800, height = 600) {
  filename <- file.path(outdir, filename)
  png(filename, width = width, height = height)
  plot(p)
  dev.off()
  Log('Wrote %s', filename)
}

# Make sure the histogram has some valid input.  If we don't do this, ggplot
# blows up with an unintuitive error message.
CheckHistogramInput <- function(v) {
  if (all(is.na(v))) {
    arg_name <- deparse(substitute(v))  # R idiom to get name
    Log('FATAL: All values in %s are NA (no successful runs?)', arg_name)
    quit(status = 1)
  }
}

WriteDistHistograms <- function(s, output_dir) {
  CheckHistogramInput(s$allocated_mass)

  p <- qplot(s$allocated_mass, geom = "histogram")
  t <- ggtitle("Allocated Mass by Task")
  x <- xlab("allocated mass")
  y <- ylab("number of tasks")
  WritePlot(p + t + x + y, output_dir, 'allocated_mass.png')

  CheckHistogramInput(s$num_rappor)

  p <- qplot(s$num_rappor, geom = "histogram")
  t <- ggtitle("Detected Strings by Task")
  x <- xlab("detected strings")
  y <- ylab("number of tasks")
  WritePlot(p + t + x + y, output_dir, 'num_rappor.png')

  CheckHistogramInput(s$num_reports)

  p <- qplot(s$num_reports / 1e6, geom = "histogram")
  t <- ggtitle("Raw Reports by Task")
  x <- xlab("millions of reports")
  y <- ylab("number of tasks")
  WritePlot(p + t + x + y, output_dir, 'num_reports.png')

  CheckHistogramInput(s$seconds)

  p <- qplot(s$seconds, geom = "histogram")
  t <- ggtitle("Analysis Duration by Task")
  x <- xlab("seconds")
  y <- ylab("number of tasks")
  WritePlot(p + t + x + y, output_dir, 'seconds.png')

  # NOTE: Skipping this for 'series' jobs.
  if (sum(!is.na(s$vm5_peak_kib)) > 0) {
    p <- qplot(s$vm5_peak_kib * 1024 / 1e6, geom = "histogram")
    t <- ggtitle("Peak Memory Usage by Task")
    x <- xlab("Peak megabytes (1e6 bytes) of memory")
    y <- ylab("number of tasks")
    WritePlot(p + t + x + y, output_dir, 'memory.png')
  }
}

ProcessAllDist <- function(s, output_dir) {
  Log('dist: Writing per-metric status.csv')
  WriteDistMetricStatus(s, output_dir)

  Log('dist: Writing histograms')
  WriteDistHistograms(s, output_dir)

  Log('dist: Writing aggregated overview.csv')
  WriteDistOverview(s, output_dir)
}

# Write the single CSV file loaded by assoc-overview.html.
WriteAssocOverview <- function(summary, output_dir) {
  s <- data.table(summary)  # data.table syntax is easier here

  by_metric <-  s[ , list(
      #params_file = unique(params_file),
      #map_file = unique(map_file),

      days = length(date),
      max_num_reports = MaybeMax(num_reports),

      # summarize status
      ok = sum(status == 'OK'),
      fail = sum(status == 'FAIL'),
      timeout = sum(status == 'TIMEOUT'),
      skipped = sum(status == 'SKIPPED'),

      mean_total_secs = MaybeMean(total_elapsed_seconds),
      mean_em_secs = MaybeMean(em_elapsed_seconds)

      ), by=list(metric)]

  # Case insensitive sort by metric name
  by_metric <- by_metric[order(tolower(by_metric$metric)), ]

  overview_path <- file.path(output_dir, 'assoc-overview.csv')
  write.csv(by_metric, file = overview_path, row.names = FALSE)
  Log("Wrote %s", overview_path)

  by_metric
}

# Write the CSV files loaded by assoc-metric.html -- that is, one
# metric-status.csv for each metric name.
WriteAssocMetricStatus <- function(summary, output_dir) {
  s <- data.table(summary)
  csv_list <- unique(s[, list(metric)])
  for (i in 1:nrow(csv_list)) {
    u <- csv_list[i, ]
    # Select cols, and convert units.  Don't need params / map / metric.
    by_pair <- s[s$metric == u$metric,
                 list(days = length(date),
                      max_num_reports = MaybeMax(num_reports),

                      # summarize status
                      ok = sum(status == 'OK'),
                      fail = sum(status == 'FAIL'),
                      timeout = sum(status == 'TIMEOUT'),
                      skipped = sum(status == 'SKIPPED'),

                      mean_total_secs = MaybeMean(total_elapsed_seconds),
                      mean_em_secs = MaybeMean(em_elapsed_seconds)
                      ),
                 by=list(var1, var2)]

    # Case insensitive sort by var1 name
    by_pair <- by_pair[order(tolower(by_pair$var1)), ]

    csv_path <- file.path(output_dir, u$metric, 'metric-status.csv')
    write.csv(by_pair, file = csv_path, row.names = FALSE)
    Log("Wrote %s", csv_path)
  }
}

# This naming convention is in task_spec.py AssocTaskSpec.
FormatAssocRelPath <- function(metric, var1, var2) {
  v2 <- gsub('..', '_', var2, fixed = TRUE)
  var_dir <- sprintf('%s_X_%s', var1, v2)
  file.path(metric, var_dir)
}

# Write the CSV files loaded by assoc-pair.html -- that is, one pair-status.csv
# for each (metric, var1, var2) pair.
WriteAssocPairStatus <- function(summary, output_dir) {

  s <- data.table(summary)

  csv_list <- unique(s[, list(metric, var1, var2)])
  Log('CSV list:')
  print(csv_list)

  # loop over unique metrics, and write a CSV for each one
  for (i in 1:nrow(csv_list)) {
    u <- csv_list[i, ]

    # Select cols, and convert units.  Don't need params / map / metric.
    subframe <- s[s$metric == u$metric & s$var1 == u$var1 & s$var2 == u$var2,
                  list(job_id, date, status,
                       num_reports, d1, d2,
                       total_elapsed_seconds,
                       em_elapsed_seconds)]

    # Sort by descending date.  Alphabetical sort works fine for YYYY-MM-DD.
    subframe <- subframe[order(subframe$date, decreasing = TRUE), ]

    pair_rel_path <- FormatAssocRelPath(u$metric, u$var1, u$var2)

    csv_path <- file.path(output_dir, pair_rel_path, 'pair-status.csv')
    write.csv(subframe, file = csv_path, row.names = FALSE)
    Log("Wrote %s", csv_path)

    # Write a file with the raw variable names.  Parsed by ui.sh, to pass to
    # csv_to_html.py.
    meta_path <- file.path(output_dir, pair_rel_path, 'pair-metadata.txt')

    # NOTE: The conversion from data.table to character vector requires
    # stringsAsFactors to work correctly!
    lines <- as.character(u)
    writeLines(lines, con = meta_path)
    Log("Wrote %s", meta_path)
  }
}

ProcessAllAssoc <- function(s, output_dir) {
  Log('assoc: Writing pair-status.csv for each variable pair in each metric')
  WriteAssocPairStatus(s, output_dir)

  Log('assoc: Writing metric-status.csv for each metric')
  WriteAssocMetricStatus(s, output_dir)

  Log('assoc: Writing aggregated overview.csv')
  WriteAssocOverview(s, output_dir)
}

main <- function(argv) {
  # increase ggplot font size globally
  theme_set(theme_grey(base_size = 16))

  action = argv[[1]]
  input = argv[[2]]
  output_dir = argv[[3]]

  if (action == 'dist') {
    summary = read.csv(input)
    ProcessAllDist(summary, output_dir)
  } else if (action == 'assoc') {
    summary = read.csv(input)
    ProcessAllAssoc(summary, output_dir)
  } else {
    stop(sprintf('Invalid action %s', action))
  }

  Log('Done')
}

if (length(sys.frames()) == 0) {
  main(commandArgs(TRUE))
}
