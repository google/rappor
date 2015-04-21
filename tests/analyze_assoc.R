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
#       $ ./analyze_assoc.R -map1 map_1.csv -map2 map_2.csv \
#                                 -reports reports.csv \
# Inputs: map1, map2, reports, params
#         see how options are parsed below for more information
# Outputs:
#         prints a table with estimated joint probability masses
#         over candidate strings
#         Ex. 
#                 ssl   nossl
#         intel   0.1   0.3
#         google  0.5   0.1

library("optparse")

options(stringsAsFactors = FALSE)

if(!interactive()) {
  option_list <- list(
    # Flags
    make_option(c("--map1", "-m1"), default = "map_1.csv",
                help = "Hashed candidates for 1st variable"),
    make_option(c("--map2", "-m2"), default = "map_2.csv",
                help = "Hashed candidates for 2nd variable"),
    make_option(c("--reports", "-r"), default = "reports.csv",
                help = "File with raw reports as <cohort, report1, report2>"),
    make_option(c("--params", "-p"), default = "params.csv",
                help = "Filename for RAPPOR parameters")
  )
  opts <- parse_args(OptionParser(option_list = option_list))
}    

source("../analysis/R/encode.R")
source("../analysis/R/decode.R")
source("../analysis/R/simulation.R")
source("../analysis/R/read_input.R")
source("../analysis/R/association.R")

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
  map$rmap <- map$map
  split_map <- function(i, map_struct) {
    numbits <- params$k
    indices <- which(as.matrix(
      map_struct[((i - 1) * numbits + 1):(i * numbits),]) == TRUE,
      arr.ind = TRUE)
    sparseMatrix(indices[, "row"], indices[, "col"],
                 dims = c(numbits, max(indices[, "col"])))
  }
  map$map <- lapply(1:params$m, function(i) split_map(i, map$rmap))
  map
}

main <- function(opts) {
  ptm <- proc.time()
  
  params <- ReadParameterFile(opts$params)
  opts_map <- list(opts$map1, opts$map2)
  map <- lapply(opts_map, function(o)
                  ProcessMap(ReadMapFile(o, params = params),
                             params = params))
  # Reports must be of the format
  #     cohort no, rappor bitstring 1, rappor bitstring 2
  reportsObj <- read.csv(opts$reports, 
                         colClasses = c("integer", "character", "character"),
                         header = FALSE)
  
  # Parsing reportsObj
  # ComputeDistributionEM allows for different sets of cohorts
  # for each variable. Here, both sets of cohorts are identical
  co <- as.list(reportsObj[1])[[1]]
  cohorts <- list(co, co)
  # Parse reports from reportObj cols 2 and 3
  reports <- lapply(1:2, function(x) as.list(reportsObj[x + 1]))
  
  # Split strings into bit arrays (as required by assoc analysis)
  reports <- lapply(1:2, function(i) {
    # apply the following function to each of reports[[1]] and reports[[2]]
    lapply(reports[[i]][[1]], function(x) {
      # function splits strings and converts them to numeric values  
      as.numeric(strsplit(x, split = "")[[1]])
    })
  })
  
  joint_dist <- ComputeDistributionEM(reports, cohorts, map, 
                                      ignore_other = TRUE,
                                      params, marginals = NULL,
                                      estimate_var = FALSE)
  # TODO(pseudorandom): Export the results to a file for further analysis
  print("JOINT_DIST$FIT")
  print(joint_dist$fit)
  print("PROC.TIME")
  print(proc.time() - ptm)
}

if(!interactive()) {
  main(opts)
}