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
        help="Use this tmp dir to communicate with the EM executable"),

    make_option(
        "--test-em-executable", dest="test_em_executable", default=FALSE,
        action="store_true",
        help="Just run a test of the EM executable (i.e. to make sure it
              exists, etc.)")
)

ParseOptions <- function() {
  # NOTE: This API is bad; if you add positional_arguments, the return value
  # changes!
  parser <- OptionParser(option_list = option_list)
  opts <- parse_args(parser)

  if (opts$test_em_executable) {  # only test validity in non-test mode
    return(opts)
  }

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

library(RJSONIO)

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

#
# Copied from Ananth's change.
#
# TODO: call it assoc_map everywhere, rename $rmap and $map fields!
# 
# - assoc_map$all_cohorts
# - assoc_map$by_cohort
#
# Then the vector can be assoc_map_list

# This function processes the maps loaded using ReadMapFile Association
# analysis requires a map object with a map field that has the map split into
# cohorts and an rmap field that has all the cohorts combined
#
# Arguments:
#       map = map object with cohorts as sparse matrix in
#             object map$map
#             This is the expected object from ReadMapFile
#       params = data field with parameters
CorrectMapForAssoc <- function(map, params, num_cores) {
  # should be map_all or something
  map$rmap <- map$map

  # should be $map_by_cohort
  map$map <- mclapply(1:params$m, function(i) {
    map$rmap[seq(from = ((i - 1) * params$k + 1),
                 length.out = params$k),]
  }, mc.cores = num_cores)  # TODO: use opts$num_cores
  map
}

# Hack to create a map for booleans.  We should use basic RAPPOR instead.
CreateBoolMap <- function(params) {
  names <- c("FALSE", "TRUE")
  by_cohort <- lapply(1:params$m, function(z) {
    # The (1,1) cell is false and the (1,2) cell is true.
    m <- sparseMatrix(c(1), c(2), dims = c(1, 2))
    colnames(m) <- names
    m
  })

  all_cohorts <- sparseMatrix(1:params$m, rep(2, params$m))
  colnames(all_cohorts) <- names

  # Make the strs stand out?
  #list(map = by_cohort, rmap = all_cohorts, strs = c("fa", "tr"))
  list(map = by_cohort, rmap = all_cohorts)
}

# Run a test of the EM executable
TestEmExecutable <- function(opts) {
  d = matrix(c(1,1,2,2,3,3), nrow=3, ncol=2)
  d = d / sum(d)

  e = matrix(c(3,3,2,2,1,1), nrow=3, ncol=2)
  e = e / sum(e)

  cond_prob = list(d, e, d)  # 3 reports
  print(cond_prob)

  em_iter_func = ConstructFastEM(opts$em_executable, opts$tmp_dir)

  em_iter_func(cond_prob, max_em_iters=4)
}

main <- function(opts) {
  if (opts$test_em_executable) {
    TestEmExecutable(opts)
    Log('Done testing EM executable')
    return()
  }

  Log("decode-assoc")

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

  # TODO: Remove these limitations.
  if (var1_type != "string") {
    UsageError("Variable 1 should be a string (%s is of type %s)", opts$var1,
               var1_type)
  }
  if (var2_type != "boolean") {
    UsageError("Variable 2 should be a boolean (%s is of type %s)", opts$var2,
               var2_type)
  }

  if (var1_type == "string") {
    if (opts$map1 == "") {
      UsageError("--map1 must be provided when --var1 is a string (var = %s)",
                 opts$var1)
    }
    # NOTE: We restore the default quote, which for some reason LoadMapFile
    # overrides.
    t <- system.time( LoadMapFile(opts$map1, quote = "\"'") )
    Log("Loading map file took %.1f seconds", t[['elapsed']])
    # for 100k map file: 31 seconds to load map and write cache; 2.2 seconds to
    # read cache
    # LoadMapFile has the side effect of putting 'map' in the global enviroment.
  }

  # Important: first column is cohort (integer); the rest are variables, which
  # are ASCII bit strings.
  reports <- read.csv(opts$reports, colClasses=c("character"), as.is = TRUE)

  N <- nrow(reports)
  Log("Read %d reports", N)
  print(head(reports))

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

  num_vars <- 2  # hard-coded for now

  # Convert strings to integers
  cohorts <- as.integer(reports$cohort)

  # Hack for Chrome: like AdjustCounts in decode_dist.R.
  cohorts <- cohorts %% params$m

  # Assume the input has 0-based cohorts, and change to 1-based cohorts.
  cohorts <- cohorts + 1

  # i.e. create a list of length 2, with identical cohorts.
  # NOTE: Basic RAPPOR doesn't need cohorts.
  cohorts_list <- rep(list(cohorts), num_vars)

  #print('COHORTS')
  #print(structure(cohorts_list))
  #print(length(cohorts_list))

  # i.e. create a list of length 2, with identical cohorts.
  string_params <- params

  bool_params <- params
  # HACK: Make this the boolean.  The Decode() step uses k.  (Note that R makes
  # a copy here)
  bool_params$k <- 1

  params_list <- list(bool_params, string_params)

  #print(structure(params_list))
  #print(length(cohorts_list))

  Log('CorrectMapForAssoc (%d cores)', opts$num_cores)
  # give it $rmap, etc.
  string_map <- CorrectMapForAssoc(map, params, opts$num_cores)

  #Log('String map:')
  #print(structure(string_map))

  Log('CreateBoolMap')
  bool_map <- CreateBoolMap(params)

  map_list <- list(bool_map, string_map)
  #print(structure(map_list))

  string_var <- reports[[opts$var1]]
  bool_var <- reports[[opts$var2]]

  Log('String Var')
  print(head(table(string_var)))
  cat('\n')

  Log('Bool Var')
  print(head(table(bool_var)))
  cat('\n')

  # Split ASCII strings into array of numerics (as required by assoc analysis)

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
  #print(structure(reports_list))

  Log('Association for %d vars', length(reports_list))

  if (opts$em_executable != "") {
    Log('Will shell out to %s for native EM implementation', opts$em_executable)
    em_iter_func = ConstructFastEM(opts$em_executable, opts$tmp_dir)
  } else {
    Log('Will use R implementation of EM (slow)')
    em_iter_func <- EM
  }

  em_result <- ComputeDistributionEM(reports_list, cohorts_list, map_list,
                                     ignore_other = FALSE,
                                     params_list = params_list,
                                     marginals = NULL,
                                    estimate_var = FALSE,
                                    num_cores = opts$num_cores,
                                    em_iter_func = em_iter_func,
                                    max_em_iters = opts$max_em_iters)
  Log("Association results:")
  fit <- em_result$fit
  print(fit)

  pretty <- apply(fit * 100, 1, function(row) sprintf("%.1f%%", row))
  Log("Percentages:")
  print(pretty)

  fit_df <- as.data.frame(fit)
  print(fit_df)

  results_csv_path <- file.path(opts$output_dir, 'assoc-results.csv')
  write.csv(fit_df, file = results_csv_path)
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
                  em_elapsed_time = em_result$em_elapsed_time)

  metrics_json_path <- file.path(opts$output_dir, 'assoc-metrics.json')
  writeLines(toJSON(metrics), con = metrics_json_path)
  Log("Wrote %s", metrics_json_path)
   
  Log('DONE decode-assoc')
}

# reports: Simulate()   EncodeAll()         sim$reports 
#  uses mclapply() and adds noise
#
# cohorts: Simulate()   SamplePopulations() truth$cohorts 
#  lapply()
#
# maps: CreateMap() in simulation.R
#   list(map, rmap, map_pos)
# params: Is this a list or not?  Uses vector-filling I guess.

# See TestComputeDistributionEM in association_test.R

if (!interactive()) {
  main(opts)
}
