#!/usr/bin/env Rscript
#
# Copyright 2015 Google Inc. All rights reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Simulates inputs on which association analysis can be run.
# Currently assoc_sim_n.R has been extended from assoc_sim.R to support N variables.
# 
# Usage:
#       $ ./assoc_sim.R -n 1000
# Inputs: uvals, params, reports, map, num, unif
#         see how options are parsed below for more information
# Outputs:
#         reports.csv file containing reports
#         map_{1, 2, ...}.csv file(s) containing maps of variables

library("optparse")

options(stringsAsFactors = FALSE)

if(!interactive()) {
  option_list <- list(
    make_option(c("--uvals", "-v"), default = "uvals.csv",
                help = "Filename for list of values over which
                distributions are simulated. The file is a list of
                comma-separated strings each line of which refers
                to a new variable."),
    make_option(c("--params", "-p"), default = "params.csv",
                help = "Filename for RAPPOR parameters"),
    make_option(c("--reports", "-r"), default = "reports.csv",
                help = "Filename for reports"),
    make_option(c("--map", "-m"), default = "map",
                help = "Filename *prefix* for map(s)"),
    make_option(c("--num", "-n"), default = 1e05,
                help = "Number of reports"),
    make_option(c("--unif", "-u"), default = FALSE,
                help = "Run simulation with uniform distribution")
  )
  opts <- parse_args(OptionParser(option_list = option_list))
}    

source("analysis/R/encode.R")
source("analysis/R/decode.R")
source("analysis/R/simulation.R")
source("analysis/R/read_input.R")
source("analysis/R/association.R")

# Read unique values of reports from a csv file
# Inputs: filename. The file is expected to contain two rows of strings
#         (one for each variable):
#         "google.com", "apple.com", ...
#         "ssl", "nossl", ...
#         "uk", "usa", "china", ...
# Returns: a list containing strings
GetUniqueValsFromFile <- function(filename) {
  contents <- read.csv(filename, header = FALSE)
  # Removes superfluous "" entries if the lists of unique values
  # differ in length
  strip_empty <- function(vec) {
    vec[!vec %in% c("")]
  }
  lapply(1:nrow(contents), function(i) strip_empty(as.vector(t(contents[i,]))))
}

# Simulate correlated reports and write into reportsfile
# Inputs: N = number of reports
#         uvals = list containing a list of unique values
#         params = list with RAPPOR parameters
#         unif = whether to replace poisson with uniform
#         mapfile = file to write maps into (with .csv suffixes)
#         reportsfile = file to write reports into (with .csv suffix)
SimulateReports <- function(N, uvals, params, unif,
                            mapfile, reportsfile) {
  # Compute true distribution
  m <- params$m  

  if (unif) {
    # Draw uniformly from 1 to 10
    v1_samples <- as.integer(runif(N, 1, 10))
  } else {
    # Draw from a Poisson random variable
    v1_samples <- rpois(N, 1) + rep(1, N)
  }
  
  # Pr[var2 = N + 1 | var1 = N] = 0.5
  # Pr[var2 = N     | var1 = N] = 0.5
  M <- length(uvals)
  Resample <- function(samples){
    N <- length(samples)
    vals <- sample(c(-1, 0, 1), N, replace = TRUE)
    unlist(lapply(1:N, function(i) if (samples[i] == 1 && vals[i] == -1) samples[i] else samples[i] + vals[i]))
  }
  v1_samples <- rpois(N, 1) + rep(1, N)
  tmp_samples <- lapply(rep(list(v1_samples), M), Resample)

  # Function to pad strings to uval_vec if sample_vec has
  # larger support than the number of strings in uval_vec
  # For e.g., if samples have support {1, 2, 3, 4, ...} and uvals
  # only have "value1", "value2", and "value3", samples now
  # over support {"value1", "value2", "value3", "str4", ...}
  PadStrings <- function(sample_vec, uval_vec) {
    if (max(sample_vec) > length(uval_vec)) {
      # Padding uvals to required length
      len <- length(uval_vec)
      max_of_samples <- max(sample_vec)
      uval_vec[(len + 1):max_of_samples] <- apply(
        as.matrix((len + 1):max_of_samples),
        1,
        function(i) sprintf("str%d", i))
    }
    uval_vec
  }
  
  # Pad and update uvals
  uvals <- lapply(1:M, function(i) PadStrings(tmp_samples[[i]],
                                              uvals[[i]]))

  # Replace integers in tmp_samples with actual sample strings
  samples <- lapply(1:M, function(i) uvals[[i]][tmp_samples[[i]]])

  # Randomly assign cohorts in each dimension
  cohorts <- sample(1:m, N, replace = TRUE)
  
  # Create and write map into mapfile_1.csv and mapfile_2.csv
  map <- lapply(uvals, function(u) CreateMap(u, params))
  res <- lapply(1:M, function(i)
        write.table(map[[i]]$map_pos, file = paste(mapfile, "_", i, ".csv", sep = ""),
                sep = ",", col.names = FALSE, na = "", quote = FALSE))

  # Write reports into a csv file
  # Format:
  #     cohort, bloom filter var1, bloom filter var2

  reports <- lapply(1:M, function(i) EncodeAll(samples[[i]], cohorts, map[[i]]$map_by_cohort, params))

  # Organize cohorts and reports into format
  write_matrix <- do.call(cbind,
                        c(list(cohorts),
                        lapply(reports, function(r)
                            unlist(lapply(r, function(x)
                                paste(x, collapse = "")))),
                        samples))
  write.table(write_matrix, file = reportsfile, quote = FALSE,
              row.names = FALSE, col.names = FALSE, sep = ",")
}

main <- function(opts) {
  ptm <- proc.time()
  
  uvals <- GetUniqueValsFromFile(opts$uvals)
  params <- ReadParameterFile(opts$params)
  SimulateReports(opts$num, uvals, params,  opts$unif, # inputs
                  opts$map, opts$reports)              # outputs
  
  print("PROC.TIME")
  print(proc.time() - ptm)
}

if(!interactive()) {
  main(opts)
}
