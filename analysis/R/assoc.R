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

# Reads map files, report files, and RAPPOR parameters to run
# an EM algorithm to estimate joint distribution over two variables one of
# which is boolean (or Basic Rappor)
#
# Usage:
#       $ ./assoc.R --inp <JSON file>
#
# Input: JSON file with the following fields
#        "maps" for map files of each var
#        "reports" for a list of reports
#        "counts" for 2 way marginal counts, individual marginal counts 
#                 respectively
#        "params" for params file with RAPPOR params
#        "results" for a file name into which results will be written
#                 as comma separated values
#
# Output: A table with joint distribution to stdout and csv file with results

library("jsonlite")
library("optparse")
library("reshape2")  # For "unrolling" joint results to csv file

options(stringsAsFactors = FALSE)

if(!interactive()) {
  option_list <- list(
    make_option(c("--inp"), default = "inp.json",
                help = "JSON file with inputs for assoc.R"))
  opts <- parse_args(OptionParser(option_list = option_list))
}

# source("analysis/R/encode.R")
source("analysis/R/decode.R")
# source("analysis/R/simulation.R")
source("analysis/R/read_input.R")
source("analysis/R/association.R")
# source("tests/gen_counts.R")

# Implements the EM algorithm on two variables
# NOTE: var 2 assumed to be reported via Basic RAPPOR
# TODO(pseudorandom): Remove this assumption on var 2.
EMAlgBasic <- function(inp) {
  ptm <- proc.time()
  params <- ReadParameterFile(inp$params)
  cat("Finished loading parameters.\n")
  # Ensure sufficient maps as required by number of vars
  stopifnot(inp$numvars == length(inp$maps))
  # Correct map from ReadMapFile() for assoc analysis
  map <- lapply(inp$maps, function(o)
    CorrectMapForAssoc(LoadMapFile(o, params = params),
                       params = params))

  cat("Finished parsing map(s).\n")
  
  # For Basic rappor, we need to setup a map file manually for var 2
  # The map file has 2 components: 
  # - an array of simple (0, 1) map to represent Basic rappor values for each
  # cohort
  # - a combined map (rmap) that collapses cohorts
  m1 <- lapply(1:params$m, function(z) {
    m <- sparseMatrix(c(1), c(2), dims = c(1, 2))
    colnames(m) <- c("FALSE", "TRUE")
    m
  })
  m2 <- sparseMatrix(1:params$m, rep(2, params$m))
  colnames(m2) <- colnames(m1[[1]])
  map[[2]]$map <- m1
  map[[2]]$rmap <- m2
  
  # Reports must be of the format
  #     client name, cohort no, rappor bitstring 1, rappor bitstring 2, ...
  # Reading to temporary data frame
  tmp_reports_df <- read.csv(inp$reports,
                             colClasses = c("character", "integer",
                                            rep("character", inp$numvars)),
                             header = TRUE)
  # Ignore the first column
  tmp_reports_df <- tmp_reports_df[,-1]
  
  # TODO(pseudorandom): Do not assume var 2 is always boolean
  # Fix which params$k is set to 1 based on which var is boolean
  # params now is a tuple of params in the standard format as required by
  # ComputeDistributionEM
  params = list(params, params)
  params[[2]]$k = 1
  
  # Parsing tmp_reports_df
  # ComputeDistributionEM allows for different sets of cohorts
  # for each variable. Here, both sets of cohorts are identical
  tmp_cohorts <- as.list(tmp_reports_df[1])$cohort
  tmp_cohorts <- tmp_cohorts + 1  # 1 indexing for EM algorithm
  # Expanded list of report cohorts
  cohorts <- rep(list(tmp_cohorts), inp$numvars)
  # Parse reports from tmp_reports_df cols 2, 3, ...
  # into a reports array
  reports <- lapply(1:inp$numvars, function(x) as.list(tmp_reports_df[x + 1]))
  
  # Split ASCII strings into array of numerics (as required by assoc analysis)
  reports <- lapply(1:inp$numvars, function(i) {
    # apply the following function to each of reports[[1]] and reports[[2]]
    # TODO(pseudorandom): Do not assume var 2 is always boolean in [[1]]
    lapply(reports[[i]][[1]], function(x) {
      # function splits strings and converts them to numeric values
      # rev needed for endianness
      rev(as.integer(strsplit(x, split = "")[[1]]))
    })
  })

  cat("Finished parsing reports.\n")
  
  # ignore_other = FALSE because in doing association with Basic RAPPOR, we're
  # going to use the Other category to estimate no. of reports where the bit
  # is unset
  # marginals and estimate_var disabled
  # verbose outputs timing information for efficiency analysis; set to inp$time
  joint_dist <- ComputeDistributionEM(reports, cohorts, map,
                                      ignore_other = FALSE,
                                      params, marginals = NULL,
                                      estimate_var = FALSE,
                                      verbose = inp$time)
  em <- joint_dist$fit
  time_taken <- proc.time() - ptm
  cat("Came here \n\n")
  # Replace Other column name with FALSE. In Basic RAPPOR we use Other
  # category to estimate no. of reports with unset bits (which are essentially
  # FALSE)
  colnames(em)[which(colnames(em) == "Other")] <- "FALSE"
  
  # Unroll and write to results.csv
  if(is.null(inp$results))
    inp$results <- "results.csv"
  write.csv(melt(em), file = inp$results, quote = FALSE,
            row.names = FALSE)
  
  print("EM Algorithm Results")
  print(em[order(-rowSums(em)), order(-colSums(em))])
  if(inp$time == TRUE)
    print(time_taken)
}

main <- function(opts) {
  inp <- fromJSON(opts$inp)
  if(inp$algo == "EM")
    EMAlgBasic(inp)
  # Recommendation: Use EMAlg; TwoWayAlgBasic is still experimental
  # and code is not completely checked in yet.
  # if(inp$algo == "2Way")
  #   TwoWayAlgBasic(inp)
}

if(!interactive()) {
  main(opts)
}
