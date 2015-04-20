#!/usr/bin/Rscript
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

library("optparse")

options(stringsAsFactors = FALSE)

if(!interactive()) {
  option_list <- list(
    make_option(c("--candidates", "-c"), default = "candidates.csv",
                help = "Filename for list of candidates over which
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

# Read candidates from a csv file
# Inputs: filename. The file is expected to contain two rows of strings
#         (one for each variable):
#         "google.com", "apple.com", ...
#         "ssl", "nossl", ...
# Returns: a list containing strings
GetCandidatesFromFile <- function(filename) {
  contents <- read.csv(filename, header = FALSE)
  # Expect 2 rows of candidates
  if(nrow(contents) != 2) {
    stop(paste("Candidate file", filename, "expected to have
               two rows of strings."))
  }
  list(var1 = as.vector(t(contents[1,])),
       var2 = as.vector(t(contents[2,])))
}

# Simulate correlated reports and write into reportsfile
# Inputs: N = number of reports
#         candidates = list containing a list of candidate strings
#         params = list with RAPPOR parameters
#         unif = whether to replace poisson with uniform
#         mapfile = file to write maps into (with .csv suffixes)
#         reportsfile = file to write reports into (with .csv suffix)
SimulateReports <- function(N, candidates, params, unif,
                            mapfile, reportsfile) {
  # Compute true distribution
  m <- params$m  
  samples <- list()

  if (unif) {
    # Draw uniformly from 1 to 10
    samples[[1]] <- as.integer(runif(N, 1, 10))
  } else {
    # Draw from a Poisson random variable
    samples[[1]] <- rpois(N, 1) + rep(1, N)
  }
  
  # Pr[var2 = N + 1 | var1 = N] = 0.5
  # Pr[var2 = N     | var1 = N] = 0.5
  samples[[2]] <- samples[[1]] + sample(c(0, 1), N, replace = TRUE)
  
  # Replace sample i with candidate i for each variable
  for(i in 1:2) {
    if(max(samples[[i]]) <= length(candidates[[i]])) {
      samples[[i]] <- candidates[[i]][samples[[i]]]
    } else {
      # Pad candidates with sample strings
      # If only 2 candidates, new set of candidates becomes:
      # candidate1, candidate2, str3, str4, ...
      len <- length(candidates)
      candidates[[i]][(len + 1):max(samples[[i]])] <- apply(
        as.matrix((len + 1):max(samples[[i]])),
        1,
        function(i) paste("str", as.character(i), sep = ""))
      samples[[i]] <- candidates[[i]][samples[[i]]]
    }
  }
  
  # Randomly assign cohorts in each dimension
  cohorts <- sample(1:m, N, replace = TRUE)
  
  # Create and write map into mapfile_1.csv and mapfile_2.csv
  map <- lapply(1:2, function(i) CreateMap(candidates[[i]], params))
  write.table(map[[1]]$map_pos, file = paste(mapfile, "_1.csv", sep = ""),
              sep = ",", col.names = FALSE, na = "", quote = FALSE)
  write.table(map[[2]]$map_pos, file = paste(mapfile, "_2.csv", sep = ""),
              sep = ",", col.names = FALSE, na = "", quote = FALSE)
  
  # Write reports into reportsfile.csv
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
  
  candidates <- GetCandidatesFromFile(opts$candidates)
  params <- ReadParameterFile(opts$params)
  SimulateReports(opts$num, candidates, params,  opts$unif, # inputs
                  opts$map, opts$reports)                   # outputs
  
  print("PROC.TIME")
  print(proc.time() - ptm)
}

if(!interactive()) {
  main(opts)
}