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
# Currently assoc_sim.R only supports 2 variables but can
# be easily extended to support more.
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

source("../analysis/R/encode.R")
source("../analysis/R/decode.R")
source("../analysis/R/simulation.R")
source("../analysis/R/read_input.R")
source("../analysis/R/association.R")

# Read unique values of reports from a csv file
# Inputs: filename. The file is expected to contain two rows of strings
#         (one for each variable):
#         "google.com", "apple.com", ...
#         "ssl", "nossl", ...
# Returns: a list containing strings
GetUniqueValsFromFile <- function(filename) {
  contents <- read.csv(filename, header = FALSE)
  # Expect 2 rows of unique vals
  if(nrow(contents) != 2) {
    stop(paste("Unique vals file", filename, "expected to have
               two rows of strings."))
  }
  # Removes superfluous "" entries if the lists of unique values
  # differ in length
  strip_empty <- function(vec) {
    vec[!vec %in% c("")]
  }
  list(var1 = strip_empty(as.vector(t(contents[1,]))),
       var2 = strip_empty(as.vector(t(contents[2,]))))
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
  v2_samples <- v1_samples + sample(c(0, 1), N, replace = TRUE)
  
  tmp_samples <- list(v1_samples, v2_samples)
  
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
  uvals <- lapply(1:2, function(i) PadStrings(tmp_samples[[i]],
                                              uvals[[i]]))

  # Replace integers in tmp_samples with actual sample strings
  samples <- lapply(1:2, function(i) uvals[[i]][tmp_samples[[i]]])

  # Randomly assign cohorts in each dimension
  cohorts <- sample(1:m, N, replace = TRUE)
  
  # Create and write map into mapfile_1.csv and mapfile_2.csv
  map <- lapply(uvals, function(u) CreateMap(u, params))
  write.table(map[[1]]$map_pos, file = paste(mapfile, "_1.csv", sep = ""),
              sep = ",", col.names = FALSE, na = "", quote = FALSE)
  write.table(map[[2]]$map_pos, file = paste(mapfile, "_2.csv", sep = ""),
              sep = ",", col.names = FALSE, na = "", quote = FALSE)
  
  # Write reports into a csv file
  # Format:
  #     cohort, bloom filter var1, bloom filter var2
  reports <- lapply(1:2, function(i)
    EncodeAll(samples[[i]], cohorts, map[[i]]$map, params))
  # Organize cohorts and reports into format
  write_matrix <- cbind(as.matrix(cohorts),
                        as.matrix(lapply(reports[[1]], 
                            function(x) paste(x, collapse = ""))),
                        as.matrix(lapply(reports[[2]],
                            function(x) paste(x, collapse = ""))))
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
