#!/usr/bin/env Rscript
#
# Command line tool to decode multidimensional reports.  It's a simple wrapper
# around functions in association.R.

library(optparse)

#
# Command line parsing.  Do this first before loading libraries to catch errors
# quickly.  Loading libraries in R is slow.
#

# Display an error string and quit.
UsageError <- function(...) {
  cat(sprintf(...))
  cat('\n')
  quit(status = 1)
}

option_list <- list(
    make_option(
        "--metric-name", dest="metric_name", default="",
        help="Name of the metric; metrics contain variables (required)"),
    make_option(
        "--reports", default="",
        help="CSV file with reports; each variable is a column (required)"),
    make_option(
        "--schema", default="",
        help="CSV file with variable types and metadata (required)"),
    make_option(
        "--params-dir", dest="params_dir", default="",
        help="Directory where parameter CSV files are stored (required)"),

    make_option(
        "--var1", default="",
        help="Name of first variable (required)"),
    make_option(
        "--var2", default="",
        help="Name of second variable (required)"),

    make_option(
        "--map1", default="",
        help="Path to map file, if var1 is a string"),
    make_option(
        "--map2", default="",
        help="Path to map file, if var2 is a string"),

    make_option(
        "--output-dir", dest="output_dir", default=".",
        help="Output directory (default .)"),

    make_option(
        "--create-bool-map", dest="create_bool_map", default=FALSE,
        action="store_true",
        help="Hack to use string RAPPOR to analyze boolean variables."),
    make_option(
        "--remove-bad-rows", dest="remove_bad_rows", default=FALSE,
        action="store_true",
        help="Whether we should remove rows where any value is missing (by 
             default, the program aborts with an error)"),

    # Options that speed it up
    make_option(
        "--reports-sample-size", dest="reports_sample_size", default=-1,
        help="Only analyze a random sample of this size.  This is for
              limiting the execution time at the expense of accuracy."),
    make_option(
        "--num-cores", dest="num_cores", default=1,
        help="Number of cores for mclapply to use.  Speeds up the parts
              of the computation proportional to the number of reports,
              EXCEPT the EM step, which can be sped up by native code."),
    make_option(
        "--max-em-iters", dest="max_em_iters", default=1000,
        help="Maximum number of EM iterations"),
    make_option(
        "--em-executable", dest="em_executable", default="",
        help="Shell out to this executable for an accelerated implementation
             of EM."),
    make_option(
        "--tmp-dir", dest="tmp_dir", default="/tmp",
        help="Use this tmp dir to communicate with the EM executable")
)

ParseOptions <- function() {
  # NOTE: This API is bad; if you add positional_arguments, the return value
  # changes!
  parser <- OptionParser(option_list = option_list)
  opts <- parse_args(parser)

  if (opts$metric_name == "") {
    UsageError("--metric-name is required.")
  }
  if (opts$reports== "") {
    UsageError("--reports is required.")
  }
  if (opts$schema == "") {
    UsageError("--schema is required.")
  }
  if (opts$params_dir == "") {
    UsageError("--params-dir is required.")
  }
  if (opts$var1 == "") {
    UsageError("--var1 is required.")
  }
  if (opts$var2 == "") {
    UsageError("--var2 is required.")
  }

  return(opts)
}

if (!interactive()) {
  opts <- ParseOptions()
}

#
# Load libraries and source our own code.
#

library(RJSONIO)  # toJSON()

# So we don't have to change pwd
source.rappor <- function(rel_path)  {
  abs_path <- paste0(Sys.getenv("RAPPOR_REPO", ""), rel_path)
  source(abs_path)
}

source.rappor("analysis/R/association.R")
source.rappor("analysis/R/fast_em.R")
source.rappor("analysis/R/read_input.R")
source.rappor("analysis/R/util.R")

options(stringsAsFactors = FALSE)
options(max.print = 100)  # So our structure() debug calls look better

CreateAssocStringMap <- function(all_cohorts_map, params) {
  # Processes the maps loaded using ReadMapFile and turns it into something
  # that association.R can use.  Namely, we want a map per cohort.
  #
  # Arguments:
  #   all_cohorts_map: map matrix, as for single variable analysis
  #   params: encoding parameters

  if (nrow(all_cohorts_map) != (params$m * params$k)) {
    stop(sprintf(
        "Map matrix has invalid dimensions: m * k = %d, nrow(map) = %d",
        params$m * params$k, nrow(all_cohorts_map)))
  }

  k <- params$k
  map_by_cohort <- lapply(0 : (params$m-1), function(cohort) {
    begin <- cohort * k
    end <- (cohort + 1) * k
    all_cohorts_map[(begin+1) : end, ]
  })

  list(all_cohorts_map = all_cohorts_map, map_by_cohort = map_by_cohort)
}

# Hack to create a map for booleans.  We should use closed-form formulas instead.
CreateAssocBoolMap <- function(params) {
  names <- c("FALSE", "TRUE")

  map_by_cohort <- lapply(1:params$m, function(unused_cohort) {
    # The (1,1) cell is false and the (1,2) cell is true.
    m <- sparseMatrix(c(1), c(2), dims = c(1, 2))
    colnames(m) <- names
    m
  })

  all_cohorts_map <- sparseMatrix(1:params$m, rep(2, params$m))
  colnames(all_cohorts_map) <- names

  list(map_by_cohort = map_by_cohort, all_cohorts_map = all_cohorts_map)
}

ResultMatrixToDataFrame <- function(m, string_var_name, bool_var_name) {
  # Args:
  #   m: A 2D matrix as output by ComputeDistributionEM, e.g.
  #          bing.com yahoo.com google.com       Other
  #   TRUE  0.2718526 0.1873424 0.19637704 0.003208933
  #   Other 0.1404581 0.1091826 0.08958427 0.001994163
  # Returns:
  #   A flattened data frame, e.g.

  # Name the dimensions of the matrix.
  dim_names <- list()
  # TODO: generalize this.  Right now we're assuming the first dimension is
  # boolean.
  dim_names[[bool_var_name]] <- c('TRUE', 'FALSE')
  dim_names[[string_var_name]] <- dimnames(m)[[2]]

  dimnames(m) <- dim_names

  # http://stackoverflow.com/questions/15885111/create-data-frame-from-a-matrix-in-r
  fit_df <- as.data.frame(as.table(m))

  # The as.table conversion gives you a Freq column.  Call it "proportion" to
  # be consistent with single variable analysis.
  colnames(fit_df)[colnames(fit_df) == "Freq"] <- "proportion" 

  fit_df
}

main <- function(opts) {
  Log("decode-assoc")
  Log("argv:")
  print(commandArgs(TRUE))

  schema <- read.csv(opts$schema)
  Log("Read %d vars from schema", nrow(schema))

  schema1 <- schema[schema$metric == opts$metric_name &
                    schema$var == opts$var1, ]
  if (nrow(schema1) == 0) {
    UsageError("Couldn't find metric '%s', field '%s' in schema",
               opts$metric_name, opts$var1)
  }
  schema2 <- schema[schema$metric == opts$metric_name &
                    schema$var== opts$var2, ]
  if (nrow(schema2) == 0) {
    UsageError("Couldn't find metric '%s', field '%s' in schema",
               opts$metric_name, opts$var2)
  }

  if (schema1$params != schema2$params) {
    UsageError('var1 and var2 should have the same params (%s != %s)',
               schema1$params, schema2$params)
  }
  params_name <- schema1$params
  params_path <- file.path(opts$params_dir, paste0(params_name, '.csv'))
  params <- ReadParameterFile(params_path)

  var1_type <- schema1$var_type
  var2_type <- schema2$var_type

  # Right now we're assuming that --var1 is a string and --var2 is a boolean.
  # TODO: Remove these limitations.
  if (var1_type != "string") {
    UsageError("Variable 1 should be a string (%s is of type %s)", opts$var1,
               var1_type)
  }
  if (var2_type != "boolean") {
    UsageError("Variable 2 should be a boolean (%s is of type %s)", opts$var2,
               var2_type)
  }

  if (opts$map1 == "") {
    UsageError("--map1 must be provided when --var1 is a string (var = %s)",
               opts$var1)
  }

  # Example cache speedup for 100k map file: 31 seconds to load map and write
  # cache; vs 2.2 seconds to read cache.
  string_params <- params
  map <- LoadMapFile(opts$map1, string_params)

  # Important: first column is cohort (integer); the rest are variables, which
  # are ASCII bit strings.
  reports <- read.csv(opts$reports, colClasses=c("character"), as.is = TRUE)

  Log("Read %d reports.  Preview:", nrow(reports))
  print(head(reports))
  cat('\n')

  # Filter bad reports first
  is_empty1 <- reports[[opts$var1]] == ""
  is_empty2 <- reports[[opts$var2]] == ""
  Log('Found %d blank values in %s', sum(is_empty1), opts$var1)
  Log('Found %d blank values in %s', sum(is_empty2), opts$var2)

  is_empty <- is_empty1 | is_empty2 # boolean vectors
  Log('%d bad rows', sum(is_empty))
  if (sum(is_empty) > 0) {
    if (opts$remove_bad_rows) {
      reports <- reports[!is_empty, ]
      Log('Removed %d rows, giving %d rows', sum(is_empty), nrow(reports))
    } else {
      stop("Found bad rows and --remove-bad-rows wasn't passed")
    }
  }

  N <- nrow(reports)

  if (N == 0) {
    # Use an arbitrary error code when there is nothing to analyze, so we can
    # distinguish this from more serious failures.
    Log("No reports to analyze.  Exiting with code 9.")
    quit(status = 9)
  }

  # Sample reports if specified.
  if (opts$reports_sample_size != -1) {
    if (N > opts$reports_sample_size) {
      indices <- sample(1:N, opts$reports_sample_size)
      reports <- reports[indices, ]
      Log("Created a sample of %d reports", nrow(reports))
    } else {
      Log("Got less than %d reports, not sampling", opts$reports_sample_size)
    }
  }

  num_vars <- 2  # hard-coded for now, since there is --var1 and --var2.

  # Convert strings to integers
  cohorts <- as.integer(reports$cohort)

  # Hack for Chrome: like AdjustCounts in decode_dist.R.
  cohorts <- cohorts %% params$m

  # Assume the input has 0-based cohorts, and change to 1-based cohorts.
  cohorts <- cohorts + 1

  # i.e. create a list of length 2, with identical cohorts.
  # NOTE: Basic RAPPOR doesn't need cohorts.
  cohorts_list <- rep(list(cohorts), num_vars)

  # TODO: We should use the closed-form formulas rather than calling the
  # solver, and not require this flag.
  if (!opts$create_bool_map) {
    stop("ERROR: pass --create-bool-map to analyze booleans.")
  }

  bool_params <- params
  # HACK: Make this the boolean.  The Decode() step uses k.  (Note that R makes
  # a copy here)
  bool_params$k <- 1

  params_list <- list(bool_params, string_params)

  Log('CreateAssocStringMap')
  string_map <- CreateAssocStringMap(map$map, params)

  Log('CreateAssocBoolMap')
  bool_map <- CreateAssocBoolMap(params)

  map_list <- list(bool_map, string_map)

  string_var <- reports[[opts$var1]]
  bool_var <- reports[[opts$var2]]

  Log('Preview of string var:')
  print(head(table(string_var)))
  cat('\n')

  Log('Preview of bool var:')
  print(head(table(bool_var)))
  cat('\n')

  # Split ASCII strings into array of numerics (as required by association.R)

  Log('Splitting string reports (%d cores)', opts$num_cores)
  string_reports <- mclapply(string_var, function(x) {
    # function splits strings and converts them to numeric values
    # rev needed for endianness
    rev(as.integer(strsplit(x, split = "")[[1]]))
  }, mc.cores = opts$num_cores)

  Log('Splitting bool reports (%d cores)', opts$num_cores)
  # Has to be an list of length 1 integer vectors
  bool_reports <- mclapply(bool_var, function(x) {
    as.integer(x)
  }, mc.cores = opts$num_cores)

  reports_list <- list(bool_reports, string_reports)

  Log('Association for %d vars', length(reports_list))

  if (opts$em_executable != "") {
    Log('Will shell out to %s for native EM implementation', opts$em_executable)
    em_iter_func <- ConstructFastEM(opts$em_executable, opts$tmp_dir)
  } else {
    Log('Will use R implementation of EM (slow)')
    em_iter_func <- EM
  }

  assoc_result <- ComputeDistributionEM(reports_list, cohorts_list, map_list,
                                        ignore_other = FALSE,
                                        params_list = params_list,
                                        marginals = NULL,
                                        estimate_var = FALSE,
                                        num_cores = opts$num_cores,
                                        em_iter_func = em_iter_func,
                                        max_em_iters = opts$max_em_iters)

  # This happens if the marginal can't be decoded.
  if (is.null(assoc_result)) {
    stop("ComputeDistributionEM failed.")
  }

  # NOTE: It would be nicer if reports_list, cohorts_list, etc. were indexed by
  # names like 'domain' rather than numbers, and the result assoc_result$fit
  # matrix had corresponding named dimensions.  Instead we call
  # ResultMatrixToDataFrame to do this.

  fit <- assoc_result$fit
  fit_df <- ResultMatrixToDataFrame(fit, opts$var1, opts$var2)

  Log("Association results:")
  print(fit_df)
  cat('\n')

  results_csv_path <- file.path(opts$output_dir, 'assoc-results.csv')
  write.csv(fit_df, file = results_csv_path, row.names = FALSE)
  Log("Wrote %s", results_csv_path)

  # Measure elapsed time as close to the end as possible
  total_elapsed_time <- proc.time()[['elapsed']]

  metrics <- list(num_reports = N,
                  reports_sample_size = opts$reports_sample_size,
                  # fit is a matrix
                  estimate_dimensions = dim(fit),
                  # should sum to near 1.0
                  sum_estimates = sum(fit),
                  total_elapsed_time = total_elapsed_time,
                  em_elapsed_time = assoc_result$em_elapsed_time,
                  num_em_iters = assoc_result$num_em_iters)

  metrics_json_path <- file.path(opts$output_dir, 'assoc-metrics.json')
  writeLines(toJSON(metrics), con = metrics_json_path)
  Log("Wrote %s", metrics_json_path)
   
  Log('DONE decode-assoc')
}

if (!interactive()) {
  main(opts)
}
