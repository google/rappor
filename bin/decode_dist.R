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
  make_option("--alpha", default=.05, help="Alpha level")
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


# Handle the case of redundant cohorts, i.e. the counts file needs to be
# further aggregated to obtain counts for the number of cohorts specified in
# the params file.
#
# NOTE: Why is this happening?
AdjustCounts <- function(counts, params) {
  apply(counts, 2, function(x) {
    tapply(x, rep(1:params$m, nrow(counts) / params$m), sum)
  })
}

ValidateInput <- function(params, counts, map) {
  val <- "valid"
  if (is.null(counts)) {
    val <- "No counts file found. Skipping"
    return(val)
  }

  if (nrow(map) != (params$m * params$k)) {
    val <- paste("Map does not match the counts file!",
                 "mk = ", params$m * params$k,
                 "nrow(map):", nrow(map),
                 collapse = " ")
  }

  if ((ncol(counts) - 1) != params$k) {
    val <- paste("Dimensions of counts file do not match:",
                 "m =", params$m, "counts rows: ", nrow(counts),
                 "k =", params$k, "counts cols: ", ncol(counts) - 1,
                 collapse = " ")
  }

  # numerically correct comparison
  if(isTRUE(all.equal((1 - params$f) * (params$p - params$q), 0)))
    stop("Information is lost. Cannot decode.")

  val
}

main <- function(opts) {
  Log("decode-dist")
  Log("argv:")
  print(commandArgs(TRUE))

  Log("Loading inputs")

  # Run a single model of all inputs are specified.
  params <- ReadParameterFile(opts$params)
  counts <- ReadCountsFile(opts$counts)

  # Count BEFORE adjustment.
  num_reports <- sum(counts[, 1])

  counts <- AdjustCounts(counts, params)

  LoadMapFile(opts$map)

  val <- ValidateInput(params, counts, map$map)  # NOTE: using global map
  if (val != "valid") {
    Log("ERROR: Invalid input: %s", val)
    quit(status = 1)
  }

  Log("Decoding %d reports", num_reports)
  res <- Decode(counts, map$map, params, correction = opts$correction, alpha =
                opts$alpha)
  Log("Done decoding")

  if (nrow(res$fit) == 0) {
    Log("FATAL: Analysis returned no strings.")
    quit(status = 1)
  }

  # Write analysis results as CSV.
  results_csv_path <- file.path(opts$output_dir, 'results.csv')
  write.csv(res$fit, file = results_csv_path, row.names = FALSE)

  res$metrics$total_elapsed_time <- proc.time()[['elapsed']]

  # Write summary as JSON (scalar values).
  metrics_json_path <- file.path(opts$output_dir, 'metrics.json')
  m <- toJSON(res$metrics)
  writeLines(m, con = metrics_json_path)
  Log("Wrote %s and %s", results_csv_path, metrics_json_path)

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
