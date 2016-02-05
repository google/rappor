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
#       $ ./assoc_sim_expt.R --inp sim_inp.json
# Inputs: uvals, params, reports, map, num, unif
#         see how options are parsed below for more information
# Outputs:
#         reports.csv file containing reports
#         map_{1, 2, ...}.csv file(s) containing maps of variables

library("jsonlite")
library("optparse")

options(stringsAsFactors = FALSE)

if(!interactive()) {
  option_list <- list(
    make_option(c("--inp"), default = "assoc_inp.json",
                help = "JSON file with inputs for assoc_sim_expt"))
  opts <- parse_args(OptionParser(option_list = option_list))
  inp <- fromJSON(opts$inp)
}

apply_prefix <- function(path) {
  paste(inp$prefix, path, sep = "")
}

source("analysis/R/encode.R")
source("analysis/R/decode.R")
source("analysis/R/simulation.R")
source("analysis/R/read_input.R")
source("analysis/R/association.R")
source("tests/gen_counts.R")

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
#         distr = the type of distribution to use
#                 {unif, poisson, poisson2, zipfg}
#         extras = whether map_1.csv has spurious candidates or not
#         truefile = name of the file with true distribution
#         varcandidates = list of number of candidates for each var
#         *** FOR ASSOCTEST TEST SUITE, USE ONLY ZIPF2 / ZIPF3 ***
#         mapfile = file to write maps into (with .csv suffixes)
#         reportsfile = file to write reports into (with .csv suffix)
SimulateReports <- function(N, uvals, params, distr, extras, truefile,
                            varcandidates,
                            mapfile, reportsfile) {
  # Compute true distribution
  m <- params$m

  if (distr == "unif") {
    # Draw uniformly from 1 to 10
    v1_samples <- as.integer(runif(N, 1, 10))

    # Pr[var2 = N + 1 | var1 = N] = 0.5
    # Pr[var2 = N     | var1 = N] = 0.5
    v2_samples <- v1_samples + sample(c(0, 1), N, replace = TRUE)

  } else if(distr == "poisson") {
    # Draw from a Poisson random variable
    v1_samples <- rpois(N, 1) + rep(1, N)

    # Pr[var2 = N + 1 | var1 = N] = 0.5
    # Pr[var2 = N     | var1 = N] = 0.5
    v2_samples <- v1_samples + sample(c(0, 1), N, replace = TRUE)
  } else if (distr == "poisson2") {

    v1_samples <- rpois(N, 1) + rep(1, N)
    # supp(var2) = {1, 2}
    # Pr[var2 = 1 | var1 = even] = 0.75
    # Pr[var2 = 1 | var1 = odd]  = 0.25
    pr25 <- rbinom(N, 1, 0.25) + 1
    pr75 <- rbinom(N, 1, 0.75) + 1
    v2_samples <- rep(1, N)
    v2_samples[v1_samples %% 2 == 0] <- pr25[v1_samples %% 2 == 0]
    v2_samples[v1_samples %% 2 == 1] <- pr75[v1_samples %% 2 == 1]
  } else if (distr == "zipf2" || distr == "zipf3") {

    var1_num <- varcandidates[[1]]
    var2_num <- varcandidates[[2]]
    
    # Zipfian over var1_num strings
    partition <- RandomPartition(N, ComputePdf("zipf1.5", var1_num))
    v1_samples <- rep(1:var1_num, partition)  # expand partition
    # Shuffle values randomly (may take a few sec for > 10^8 inputs)
    v1_samples <- sample(v1_samples)

    # supp(var2) = {1, 2, 3, ..., var2_num}
    # We look at two zipfian distributions over supp(var2)
    # D1 = zipfian distribution
    # D2 = zipfian distr over {var2_num, ..., 4, 3, 2, 1}
    # (i.e., D1 in reverse)
    # var2 ~ D1 if var1 = even
    # var2 ~ D2 if var1 = odd
    d1 <- sample(rep(1:var2_num,
                     RandomPartition(N, ComputePdf("zipf1.5", var2_num))))
    d2 <- (var2_num:1)[d1]
    v2_samples <- rep(1, N)
    v3_samples <- rep(1, N)
    v2_samples[v1_samples %% 2 == 0] <- d1[v1_samples %% 2 == 0]
    v2_samples[v1_samples %% 2 == 1] <- d2[v1_samples %% 2 == 1]
    if(distr == "zipf3") {
      bool1 <- rbinom(N, 1, 0.25) + rep(1, N)
      bool2 <- rbinom(N, 1, 0.75) + rep(1, N)
      v3_samples[v1_samples %% 2 == 0] <- bool1[v1_samples %% 2 == 0]
      v3_samples[v1_samples %% 2 == 1] <- bool2[v1_samples %% 2 == 1]
    }
  }

  if(length(varcandidates) == 3) {
    tmp_samples <- list(v1_samples, v2_samples, v3_samples)
  } else if (length(varcandidates) == 2) {
    tmp_samples <- list(v1_samples, v2_samples)
  }

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
  uvals <- lapply(1:length(varcandidates),
                  function(i) PadStrings(tmp_samples[[i]],
                                              uvals[[i]]))
  # Replace integers in tmp_samples with actual sample strings
  samples <- lapply(1:length(varcandidates),
                    function(i) uvals[[i]][tmp_samples[[i]]])

  print("TRUE DISTR")
  td <- table(samples)/sum(table(samples))
  if (length(varcandidates) == 2) {
    td <- td[order(rowSums(td), decreasing = TRUE),]
  } else {
    td <- td[order(rowSums(td), decreasing = TRUE),,]
  }
  print(td)
  write.table(td, file = truefile, sep = ",", col.names = TRUE,
              row.names = TRUE, quote = FALSE)
  # Randomly assign cohorts in each dimension
  cohorts <- sample(1:m, N, replace = TRUE)

  # Create and write map into mapfile_1.csv and mapfile_2.csv
  if (extras > 0) {
    # spurious candidates for mapfile_1.csv
    len <- length(uvals[[1]]) + as.numeric(extras)
    uvals[[1]] <- PadStrings(len, uvals[[1]])
  }
  map <- lapply(uvals, function(u) CreateMap(u, params))
  write.table(map[[1]]$map_pos, file = paste(mapfile, "_1.csv", sep = ""),
                sep = ",", col.names = FALSE, na = "", quote = FALSE)
  write.table(map[[2]]$map_pos, file = paste(mapfile, "_2.csv", sep = ""),
              sep = ",", col.names = FALSE, na = "", quote = FALSE)
  if(length(varcandidates) == 3) {
    write.table(map[[3]]$map_pos, file = paste(mapfile, "_3.csv", sep = ""),
              sep = ",", col.names = FALSE, na = "", quote = FALSE)
  }

  # Write reports into a csv file
  # Format:
  #     cohort, bloom filter var1, bloom filter var2
  reports <- lapply(1:length(varcandidates), function(i)
    EncodeAll(samples[[i]], cohorts, map[[i]]$map, params))
  # Organize cohorts and reports into format
  write_matrix <- cbind(as.matrix(cohorts),
                        sapply(reports,
                               function(x) as.matrix(lapply(x,
                                                            function(z) paste(z, collapse = "")))))
  write.table(write_matrix, file = reportsfile, quote = FALSE,
              row.names = FALSE, col.names = FALSE, sep = ",")
}

main <- function(inp) {
  ptm <- proc.time()
  
  if(is.null(inp$uvals)) {
    # One off case.
    # TODO(pseudorandom): More sensible defaults.
    uvals = list(var1 = c("str1", "str2"), var2 = c("option1", "option2"))
  } else {
    uvals <- GetUniqueValsFromFile(apply_prefix(inp$uvals))
  }
  params <- ReadParameterFile(apply_prefix(inp$params))
  SimulateReports(inp$num, uvals, params,  inp$distr,   # inuts
                  inp$extras,  apply_prefix(inp$true),  # inputs
                  inp$varcandidates,          # inputs
                  apply_prefix(inp$map),
                  apply_prefix(inp$reports))             # outputs

  print("PROC.TIME")
  print(proc.time() - ptm)
}

if(!interactive()) {
  main(inp)
}
