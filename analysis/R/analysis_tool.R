#!/usr/bin/env Rscript
#
# IMPORTANT: This script should be deleted when the analysis server is ready.
#
# Generates daily Chrome RAPPOR feed. All experiments found in the
# experiment_config flag are processed for each day.
#
# If neither start_date nor end_date are specified, the feed runs on
# yesterday's data by default. Otherwise, a date range could be indicated
# to run a backfill.
#
# num_days indicates how many days should be aggregated over. If num_days = 7,
# then 7-day trailing (combining data from the most recent 7 days) analysis for
# each date (by default, only for yesterday) will be performed. Please use 7
# days for weekly and 28 days for monthly analyses.

library(optparse)

source("analysis/R/analysis_lib.R")
source("analysis/R/read_input.R")
source("analysis/R/decode.R")

source("analysis/R/alternative.R")

options(stringsAsFactors = FALSE)

# Do command line parsing first to catch errors.  Loading libraries in R is
# slow.
if (!interactive()) {
  option_list <- list(
    # Flags.
    make_option("--start_date", default="", help="First date to process. Format: %Y/%m/%d"),
    make_option("--end_date", default="", help="Last date to process"),
    make_option("--num_days", default=1, help="Number of trailing days to process"),

    make_option("--experiment_config", default="chrome_rappor_experiments.csv",
                help="Experiment config file"),
    make_option("--map", default="MA", help="Map file"),
    make_option("--counts", default="CO", help="Counts file"),
    # TODO: Rename this to --params
    make_option("--config", default="", help="Config file"),
    make_option("--output_dir", default="./", help="Output directory"),

    make_option("--correction", default="FDR", help="Correction method"),
    make_option("--alpha", default=.05, help="Alpha level"),

    # Input and output directories.
    make_option("--counts_dir", default="/cns/pa-d/home/chrome-rappor/daily",
                help="CNS directory where counts files are located"),
    make_option("--map_dir", default="/cns/pa-d/home/chrome-rappor/map",
                help="CNS map directory"),
    make_option("--config_dir", default="/cns/pa-d/home/chrome-rappor/config",
                help="CNS configuration files directory"),
    make_option("--release_dir", default="/cns/pa-d/home/chrome-rappor/release",
                help="Output directory")
  )
  # NOTE: This API is bad; if you add positional_arguments, the return value changes!
  opts <- parse_args(OptionParser(option_list = option_list))
}

# NOTE: This is in tests/analysis.R too
Log <- function(...) {
  cat('rappor_analysis.R: ')
  cat(sprintf(...))
  cat('\n')
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

RunOne <- function(opts) {
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

  results_path <- file.path(opts$output_dir, 'results.csv')
  write.csv(fit, file = results_path, row.names = FALSE)

  # TODO:
  # - These are in an 2 column 'parameters' and 'values' format.  Should these
  # just be a plain list?
  # - Write them to another CSV file or JSON on stdout?

  Log("Fit summary:")
  print(res$summary)
  cat("\n")

  Log("Privacy summary:")
  print(res$privacy)
  cat("\n")

  # Output metrics as machine-parseable prefix + JSON.
  num_rappor <- nrow(fit)
  allocated_mass <- sum(fit$proportion)
  Log('__OUTPUT_METRICS__ {"num_rappor": %d, "allocated_mass": %f}',
      num_rappor, allocated_mass)

  Log('DONE')
}

# Run multiple models.  There is a CSV experiments config file, and we invoke
# AnalyzeRAPPOR once for each row in it.
RunMany <- function(opts) {

  # If the date is not specified, run yesterday's analyses only.
  if (opts$start_date == "" && opts$end_date == "") {
    start_date <- Sys.Date() - 1
    end_date <- start_date
  } else {
    start_date <- as.Date(opts$start_date)
    end_date <- as.Date(opts$end_date)
    if (end_date < start_date) {
      stop("End date should be larger or equal than start date!")
    }
  }
  dates <- as.character(seq(start_date, end_date, 1))

  # List of experiments to analyze.
  config_path = file.path(opts$config_dir, opts$experiment_config)
  Log('Reading experiment config %s', config_path)
  experiments <- read.csv(config_path,
                          header = FALSE, as.is = TRUE,
                          colClasses = "character", comment.char = "#")

  for (date in dates) {
    Log("Date: %s", date)
    date <- as.Date(date)
    year <- format(date, "%Y")
    month <- format(date, "%m")
    day <- format(date, "%d")

    # Create an output directory.
    output_dir <- file.path(opts$release_dir, year, month, day)
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

    base_filename <- "chrome_rappor_experiments_"
    output_filename <-
      switch(as.character(opts$num_days),
             "1" = paste0(base_filename, date, ".csv"),
             "7" = paste0("weekly_", base_filename, date, ".csv"),
             "28" = paste0("monthly_", base_filename, date, ".csv"),
             paste0(opts$num_days, "_", base_filename, date, ".csv"))

    # Delete any existing files with the same name.
    unlink(file.path(output_dir, output_filename))

    res <- vector("list", nrow(experiments))
    for (i in 1:nrow(experiments)) {
      cat(paste0("Experiment ", i, " (of ",
                 nrow(experiments), "): ", experiments[i, 2], "\n"))

      # Process a line in the experiments file.
      experiment_name <- experiments[i, 2]
      map_file <- experiments[i, 3]
      config_file <- experiments[i, 4]

      # Read in input files specified in the experiments file.
      params_path = file.path(opts$config_dir, config_file)
      Log('Reading params %s', params_path)
      config <- ReadParameterFile(params_path)

      map_path <- file.path(opts$map_dir, map_file)
      Log('Loading map %s', map_path)
      LoadMapFile(map_path)  # Loads the "map" object.

      # Read one or more counts file.
      counts_file <- paste0(experiments[i, 1], "_counts.csv")
      trailing_dates <- as.character(seq(date - opts$num_days + 1, date, 1))
      counts_list <- list()
      for (j in 1:length(trailing_dates)) {
        counts_path = file.path(opts$counts_dir, trailing_dates[j], counts_file)
        Log("Reading counts %s", counts_path)

        counts_j <- ReadCountsFile(file.path(opts$counts_dir,
                                             trailing_dates[j], counts_file))
        if (!is.null(counts_j)) {
          counts_list[[j]] <- AdjustCounts(counts_j, config)
        }
      }
      counts <- Reduce("+", counts_list)  # Turn list into matrix

      # Perform the analysis.

      Log("CONFIG")
      str(config)
      cat('\n')

      Log("COUNTS")
      str(counts)
      cat('\n')

      Log("MAP")
      str(map$map)
      cat('\n')

      exp_res <- AnalyzeRAPPOR(config, counts, map$map, opts$correction, opts$alpha,
                               experiment_name = experiment_name,
                               map_name = map_file,
                               config_name = config_file,
                               date = as.character(date),
                               date_num = as.numeric(format(date, "%Y%m%d")))

      if (!is.null(exp_res)) {
        res[[i]] <- exp_res
        cat("Discovered:", nrow(exp_res), "\n\n")
      } else {
        cat("Discovered: 0\n\n")
      }
    }

    # Write out a single column IO file for each date.
    output <- do.call("rbind", res)
    if (!is.null(output) && nrow(output) > 0) {
      path = file.path(output_dir, output_filename)
      write.csv(output, path)
      Log('Wrote %s', path)
    }

    Log("RES")
    str(res)
    cat('\n')

    Log("OUTPUT")
    str(output)
    cat('\n')

    Log("sum(proportion)")
    print(sum(output$proportion))

    Log("sum(estimate)")
    print(sum(output$estimate))
  }
}

main = function(opts) {
  if (opts$counts != "" && opts$map != "" && opts$config != "") {
    RunOne(opts)
  } else {
    RunMany(opts)
  }
}

if (!interactive()) {
  main(opts)
}
