#!/usr/bin/env Rscript
#
# Command line tool to decode a RAPPOR data set.  It is a simple wrapper for
# Decode() in decode.R.

library(optparse)
library(RJSONIO)

source("analysis/R/read_input.R")
source("analysis/R/decode.R")
source("analysis/R/util.R")

options(stringsAsFactors = FALSE)

# Do command line parsing first to catch errors.  Loading libraries in R is
# slow.
if (!interactive()) {
  option_list <- list(
    # Flags.
    make_option("--map", default="MA", help="Map file"),
    make_option("--counts", default="CO", help="Counts file"),
    # TODO: Rename this to --params
    make_option("--config", default="", help="Config file"),

    make_option("--output_dir", default="./", help="Output directory"),

    make_option("--correction", default="FDR", help="Correction method"),
    make_option("--alpha", default=.05, help="Alpha level")
  )
  # NOTE: This API is bad; if you add positional_arguments, the return value changes!
  opts <- parse_args(OptionParser(option_list = option_list))
}

# Handle the case of redundant cohorts, i.e. the counts file needs to be
# further aggregated to obtain counts for the number of cohorts specified in
# the config file.
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
  # Run a single model of all inputs are specified.
  params <- ReadParameterFile(opts$config)
  counts <- ReadCountsFile(opts$counts)

  # Count BEFORE adjustment.
  num_reports <- sum(counts[, 1])
  Log("Number of reports: %d", num_reports)

  counts <- AdjustCounts(counts, params)

  # NOTE: We restore the default quote, which for some reason LoadMapFile
  # overrides.
  LoadMapFile(opts$map, quote = "\"'")

  val <- ValidateInput(params, counts, map$map)  # NOTE: using global map
  if (val != "valid") {
    Log("ERROR: Invalid input: %s", val)
    quit(status = 1)
  }

  res <- Decode(counts, map$map, params, correction = opts$correction, alpha =
                opts$alpha)

  if (nrow(res$fit) == 0) {
    Log("FATAL: Analysis returned no strings.")
    quit(status = 1)
  }

  fit <- res$fit

  # Write analysis results as CSV.
  results_csv_path <- file.path(opts$output_dir, 'results.csv')
  write.csv(fit, file = results_csv_path, row.names = FALSE)

  # Dump residual histograph as png.
  results_png_path <- file.path(opts$output_dir, 'residual.png')
  png(results_png_path)
  breaks <- pretty(res$residual, n = 200)
  step <- breaks[2] - breaks[1]  # distance between bins
  histogram <- hist(res$residual, breaks, plot = FALSE)
  histogram$counts <- histogram$counts / sum(histogram$counts)  # conver the histogram to frequencies
  plot(histogram,
  		 main = "Histogram of the residual")
  lapply(res$humps, function(hump) {
  	gaussian <- function(x) dnorm(x, mean = hump$mean, sd = hump$sd) * hump$mass * step
  	points_x <- c(breaks, rev(breaks))  # there and back
  	points_y <- c(rep(0, length(breaks)), rev(gaussian(breaks)))
  	polygon(points_x, points_y, col = adjustcolor("blue", alpha.f=0.3), border = NA)
  	curve(gaussian, add = TRUE)} )
  dev.off()

  # Write summary as JSON (scalar values).
  metrics_json_path <- file.path(opts$output_dir, 'metrics.json')
  m <- toJSON(res$metrics)
  writeLines(m, con = metrics_json_path)

  # TODO:
  # - These are in an 2 column 'parameters' and 'values' format.  Should these
  # just be a plain list?
  # - Should any of these privacy params be in metrics.json?

  Log("Privacy summary:")
  print(res$privacy)
  cat("\n")

  # Output metrics as machine-parseable prefix + JSON.
  Log('__OUTPUT_METRICS__ {"num_rappor": %d, "allocated_mass": %f}',
      res$metrics$num_detected, res$metrics$allocated_mass)

  Log('DONE')
}

if (!interactive()) {
  main(opts)
}
