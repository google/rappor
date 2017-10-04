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
# an EM algorithm to estimate joint distribution over two or more variables
# 
# Usage:
#       $ ./analyze_assoc.R -map map_1.csv map_2.csv ... map_n.csv \
#                                 -reports reports.csv \
# Inputs: map1, map2,... mapn, reports, params
#         see how options are parsed below for more information
# Outputs:
#         prints a table with estimated joint probability masses
#         over candidate strings
#         Ex. 
#                 ssl   nossl
#         intel   0.1   0.3
#         google  0.5   0.1

library("argparse")
library("glmnet")

options(stringsAsFactors = FALSE)

if(!interactive()) {
  parser <- ArgumentParser()
    # Flags
  parser$add_argument("-m", "--map", metavar='N', nargs='+',
                help = "Hashed candidates 1..N")
  parser$add_argument("-r", "--reports", default = "reports.csv",
                help = "File with raw reports as <cohort, report1 .. reportN>")
  parser$add_argument("-p", "--params", default = "params.csv",
                help = "Filename for RAPPOR parameters")

#  opts <- parse_args(OptionParser(option_list = option_list))
#  opts <- commandArgs(trailingOnly = TRUE)
  opts <- parser$parse_args()
}

source("analysis/R/encode.R")
source("analysis/R/decode.R")
source("analysis/R/simulation.R")
source("analysis/R/read_input.R")
source("analysis/R/association.R")
# This function processes the maps loaded using ReadMapFile
# Association analysis requires a map object with a map
# field that has the map split into cohorts and an rmap field
# that has all the cohorts combined
# Arguments:
#       map = map object with cohorts as sparse matrix in
#             object map$map
#             This is the expected object from ReadMapFile
#       params = data field with parameters
# TODO(pseudorandom): move this functionality to ReadMapFile
ProcessMap <- function(map, params) {
  map$all_cohorts_map <- map$map
  split_map <- function(i, map_struct) {
    numbits <- params$k
    indices <- which(as.matrix(
      map_struct[((i - 1) * numbits + 1):(i * numbits),]) == TRUE,
      arr.ind = TRUE)
    map_by_cohort <- sparseMatrix(indices[, "row"], indices[, "col"],
                 dims = c(numbits, max(indices[, "col"])))
    colnames(map_by_cohort) <- colnames(map_struct)
    map_by_cohort
  }
  map$map_by_cohort <- lapply(1:params$m, function(i) split_map(i, map$all_cohorts_map))
  map
}

main <- function(opts) {
  ptm <- proc.time()

  params <- ReadParameterFile(opts$params)
  map <- lapply(opts$map, function(o)
                  ProcessMap(ReadMapFile(o, params = params),
                             params = params))
  N <- length(opts$map)
  # Reports must be of the format
  #     cohort no, rappor bitstring 1.. rappor bitstring N
  reportsObj <- read.csv(opts$reports,
                         colClasses = c("integer", rep("character", 2*N)),
                         header = FALSE)

  # Parsing reportsObj
  # ComputeDistributionEM allows for different sets of cohorts
  # for each variable. Here, both sets of cohorts are identical
  co <- as.list(reportsObj[1])[[1]]
  cohorts <- rep(list(co), N)
  # Parse reports from reportObj cols 2 and 3
  reports <- lapply(2:(N+1), function(x) as.list(reportsObj[x]))

  # Split strings into bit arrays (as required by assoc analysis)
  reports <- lapply(1:N, function(i) {
    # apply the following function to each of reports[[1]] and reports[[2]]
    lapply(reports[[i]][[1]], function(x) {
      # function splits strings and converts them to numeric values
      as.numeric(strsplit(x, split = "")[[1]])
    })
  })

  joint_dist <- ComputeDistributionEM(reports, cohorts, map,
                                      ignore_other = TRUE,
                                      params, marginals = NULL,
                                      estimate_var = TRUE)
  # TODO(pseudorandom): Export the results to a file for further analysis
  print("JOINT_DIST$FIT")
  print(joint_dist$fit)
  print("JOINT_DIST$SUM")
  x <- joint_dist$fit
  y <- cbind(x, rowSums(x))
  z <- rbind(y, colSums(y))
  print(rowSums(joint_dist$fit))
  print(colSums(joint_dist$fit))
  print(z[length(z)])
  print("JOINT_DIST$SD")
  print(joint_dist$sd)
  print("JOINT_DIST$VAR-COV")
  print(joint_dist$var_cov)
  print("PROC.TIME")
  print(proc.time() - ptm)
}

if(!interactive()) {
  main(opts)
}