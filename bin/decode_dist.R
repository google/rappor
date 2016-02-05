#!/usr/bin/env Rscript
#
# Command line tool to decode a RAPPOR data set.  It is a simple wrapper for
# Decode() in decode.R.

library(optparse)

#
# Command line parsing.  Do this first before loading libraries to catch errors
# quickly.  Loading libraries in R is slow.
#

# For command line error checking.
UsageError <- function(...) {
  cat(sprintf(...))
  cat('\n')
  quit(status = 1)
}

option_list <- list(
  # Inputs
  make_option("--map", default="", help="Map file (required)"),
  make_option("--counts", default="", help="Counts file (required)"),
  make_option("--params", default="", help="Params file (required)"),
  make_option("--output-dir", dest="output_dir", default=".",
              help="Output directory (default .)"),

  make_option("--correction", default="FDR", help="Correction method"),
  make_option("--alpha", default=.05, help="Alpha level"),

  make_option("--adjust-counts-hack", dest="adjust_counts_hack",
              default=FALSE, action="store_true",
              help="Allow the counts file to have more rows than cohorts. 
                    Most users should not use this.")
)

ParseOptions <- function() {
  # NOTE: This API is bad; if you add positional_arguments, the return value
  # changes!
  parser <- OptionParser(option_list = option_list)
  opts <- parse_args(parser)

  if (opts$map == "") {
    UsageError("--map is required.")
  }
  if (opts$counts == "") {
    UsageError("--counts is required.")
  }
  if (opts$params == "") {
    UsageError("--params is required.")
  }
  return(opts)
}

if (!interactive()) {
  opts <- ParseOptions()
}

#
# Load libraries and source our own code.
#

library(RJSONIO)

# So we don't have to change pwd
source.rappor <- function(rel_path)  {
  abs_path <- paste0(Sys.getenv("RAPPOR_REPO", ""), rel_path)
  source(abs_path)
}

source.rappor("analysis/R/read_input.R")
source.rappor("analysis/R/decode.R")
source.rappor("analysis/R/util.R")

source.rappor("analysis/R/alternative.R")

options(stringsAsFactors = FALSE)


main <- function(opts) {
  Log("decode-dist")
  Log("argv:")
  print(commandArgs(TRUE))

  Log("Loading inputs")

  # Run a single model of all inputs are specified.
  params <- ReadParameterFile(opts$params)
  counts <- ReadCountsFile(opts$counts, params, adjust_counts = opts$adjust_counts_hack)
  counts <- AdjustCounts(counts, params)


  # The left-most column has totals.
  num_reports <- sum(counts[, 1])

  map <- LoadMapFile(opts$map, params)

  Log("Decoding %d reports", num_reports)
  res <- Decode(counts, map$map, params, correction = opts$correction,
                alpha = opts$alpha)
  Log("Done decoding")

  if (nrow(res$fit) == 0) {
    Log("FATAL: Analysis returned no strings.")
    quit(status = 1)
  }

  # Write analysis results as CSV.
  results_csv_path <- file.path(opts$output_dir, 'results.csv')
  write.csv(res$fit, file = results_csv_path, row.names = FALSE)

  # Write residual histograph as a png.
  results_png_path <- file.path(opts$output_dir, 'residual.png')
  png(results_png_path)
  breaks <- pretty(res$residual, n = 200)
  histogram <- hist(res$residual, breaks, plot = FALSE)
  histogram$counts <- histogram$counts / sum(histogram$counts)  # convert the histogram to frequencies
  plot(histogram, main = "Histogram of the residual",
       xlab = sprintf("Residual (observed - explained, %d x %d values)", params$m, params$k))
  dev.off()

  res$metrics$total_elapsed_time <- proc.time()[['elapsed']]

  # Write summary as JSON (scalar values).
  metrics_json_path <- file.path(opts$output_dir, 'metrics.json')
  m <- toJSON(res$metrics)
  writeLines(m, con = metrics_json_path)
  Log("Wrote %s, %s, and %s", results_csv_path, results_png_path, metrics_json_path)

  # TODO:
  # - These are in an 2 column 'parameters' and 'values' format.  Should these
  # just be a plain list?
  # - Should any of these privacy params be in metrics.json?

  Log("Privacy summary:")
  print(res$privacy)
  cat("\n")

  Log('DONE')
}

if (!interactive()) {
  main(opts)
}
