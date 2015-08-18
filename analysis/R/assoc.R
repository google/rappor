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
#       $ ./assoc.R --inp <JSON file>
#
# Input: JSON file with the following fields
#        "maps" for map files of each var
#        "reports" for a list of reports
#        "counts" for 2 way marginal counts, individual marginal counts 
#                 respectively
#        "params" for params file with RAPPOR params
#        "csv_out" for a file name into which results will be written
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

source("analysis/R/decode2way.R")
source("analysis/R/encode.R")
source("analysis/R/decode.R")
source("analysis/R/simulation.R")
source("analysis/R/read_input.R")
source("analysis/R/association.R")
source("tests/gen_counts.R")
source("tests/compare_assoc.R")  # For CombineMaps; it should be moved elsewhere

# Analysis where second variable is basic RAPPOR
TwoWayAlgBasic <- function(inp) {
  ptm <- proc.time()
  params <- ReadParameterFileMulti(inp$params)
  stopifnot(inp$numvars == length(inp$maps) ||
              inp$numvars == length(params))
  map <- CorrectMapForAssoc(ReadMapFile(inp$maps[[1]], params = params[[1]]),
                            params = params[[1]])
  
  # 2 way counts, marginal 1 counts, marginal 2 counts
  counts <- lapply(1:3, function(i) ReadCountsFile(inp$counts[[i]]))
  
  # Prune candidates for variable 1
  fit <- Decode(counts[[2]], map$rmap, params[[1]], quick = FALSE)$fit
  print(fit)
  found_strings <- fit[,"string"]
  
  if(length(found_strings) == 0)
    stop("No strings found in 1-way marginal.")
  
  pruned_map <- lapply(map$map, function(z) z[,found_strings, drop = FALSE])
  map2 <- lapply(1:length(pruned_map), function(z) {
    m <- sparseMatrix(c(1), c(2), dims = c(1, 2))
    colnames(m) <- c("FALSE", "TRUE")
    m
  })
  # Final map
  fmap <- CombineMaps(pruned_map, map2)$crmap
  params2 <- params[[1]]
  # Only for boolean
  params2$k <- (params[[1]]$k) * 4
  # Get true values (for debug purposes only)
  truevals <- read.csv(inp$truevals)[,c("value1", "value2")]
  truevals <- table(truevals) / sum(table(truevals))
  colnames(truevals) <- c("FALSE", "TRUE")
  marginal <- Decode2Way(counts[[1]], fmap, params2,
                         fit = fit[,c("string", "proportion")])$fit
  rs <- rowSums(truevals)
  fits <- data.frame(string = rownames(as.data.frame(rs)),
                     proportion = as.vector(rs))
  truecol = NULL
  for (rows in found_strings) {
    for (cols in c("FALSE", "TRUE")) {
      truecol <- c(truecol, truevals[rows, cols])
    }
  }
  marginal <- cbind(marginal, true = truecol)
  for (i in -3:3) {
    fits_t <- fits
    fits_t[,"proportion"] <- fits_t[,"proportion"] * (1 + i/10)
    marginal <- cbind(marginal,
                      more = Decode2Way(counts[[1]],
                                 fmap,
                                 params2,
                                 fit = fits_t)$fit[,"Estimate"])
    print("ABS")
    print(0.5 * sum(abs(marginal$true-marginal[,i + 8])))
  }
  ed <- matrix(0, nrow = length(found_strings), ncol = 2)
  colnames(ed) <- c("FALSE", "TRUE")
  rownames(ed) <- found_strings
  for (rows in rownames(ed)) {
    for (cols in colnames(ed)) {
      ed[rows, cols] <- marginal[paste(rows, cols, sep = "x"), "Estimate"] 
    }
  }

  print(marginal)
  print(sum(marginal[,"Estimate"]))
  ed[is.na(ed)] <- 0
  ed[ed<0] <- 0
  
  time_taken <- proc.time() - ptm
  print("Two Way Algorithm Results")
  # print(ed)
  # print(ed[order(-rowSums(ed)), order(-colSums(ed))])
}

TwoWayAlg <- function(inp) {
  ptm <- proc.time()
  params <- ReadParameterFile(inp$params)
  # Ensure sufficient maps as required by number of vars
  # Correct map from ReadMapFile() for assoc analysis
  stopifnot(inp$numvars == length(inp$maps))
  map <- lapply(inp$maps, function(o)
    CorrectMapForAssoc(ReadMapFile(o, params = params),
                       params = params))
  
  # (2 way counts, marginal 1 counts, marginal 2 counts)
  counts <- lapply(1:3, function(i) ReadCountsFile(inp$counts[[i]]))
  
  # TODO: account for different parameters across different variables
  params2 <- params
  params2$k <- (params$k ** 2) * 4
  
  # Prune candidates
  fit <- lapply(1:2, function(i)
    Decode(counts[[i + 1]],
           map[[i]]$rmap,
           params, quick = FALSE)$fit)
  
  found_strings = list(fit[[1]][,"string"], fit[[2]][,"string"])
  
  if (length(found_strings[[1]]) == 0 || length(found_strings[[2]]) == 0) {
    stop("No strings found in 1-way marginal.")
  }
  
  # Combine maps to feed into Decode2Way
  # Prune first to found_strings from Decode on 1-way counts
  pruned <- lapply(1:2, function(i)
    lapply(map[[i]]$map, function(z) z[,found_strings[[i]], drop = FALSE]))
  crmap <- CombineMaps(pruned[[1]], pruned[[2]])$crmap
  marginal <- Decode2Way(counts[[1]], crmap, params2, fit = fit)$fit
  
  # Reconstruct 2-way table from marginals
  ed <- matrix(0, nrow = length(found_strings[[1]]), ncol = length(found_strings[[2]]))
  colnames(ed) <- found_strings[[2]]
  rownames(ed) <- found_strings[[1]]
  for (cols in found_strings[[2]]) {
    for (rows in found_strings[[1]]) {
      ed[rows, cols] <- marginal[paste(rows, cols, sep = "x"), "Estimate"]
    }
  }
  ed[is.na(ed)] <- 0
  ed[ed<0] <- 0
  
  time_taken <- proc.time() - ptm
  print("Two Way Algorithm Results")
  print(ed[order(-rowSums(ed)), order(-colSums(ed))])
  if(inp$time == TRUE)
    print(time_taken)
}

EMAlg <- function(inp) {
  ptm <- proc.time()
  params <- ReadParameterFile(inp$params)
  # Ensure sufficient maps as required by number of vars
  stopifnot(inp$numvars == length(inp$maps))
  # Correct map from ReadMapFile() for assoc analysis
  map <- lapply(inp$maps, function(o)
    CorrectMapForAssoc(LoadMapFile(o, params = params),
                       params = params))
  
  # For BASIC only
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
  reportsObj <- read.csv(inp$reports,
                         colClasses = c("character", "integer",
                                        rep("character", inp$numvars)),
                         header = TRUE)
  # Ignore the first column
  reportsObj <- reportsObj[,-1]
  
  params = list(params, params)
  params[[2]]$k = 1
  
  # Parsing reportsObj
  # ComputeDistributionEM allows for different sets of cohorts
  # for each variable. Here, both sets of cohorts are identical
  co <- as.list(reportsObj[1])[[1]]
  co <- co + 1  # 1 indexing
  cohorts <- rep(list(co), inp$numvars)
  # Parse reports from reportObj cols 2, 3, ...
  reports <- lapply(1:inp$numvars, function(x) as.list(reportsObj[x + 1]))
  
  # Split strings into bit arrays (as required by assoc analysis)
  reports <- lapply(1:inp$numvars, function(i) {
    # apply the following function to each of reports[[1]] and reports[[2]]
    lapply(reports[[i]][[1]], function(x) {
      # function splits strings and converts them to numeric values
      # rev needed for endianness
      rev(as.numeric(strsplit(x, split = "")[[1]]))
    })
  })
  
  joint_dist <- ComputeDistributionEM(reports, cohorts, map,
                                      ignore_other = FALSE,
                                      quick = TRUE,
                                      params, marginals = NULL,
                                      estimate_var = FALSE,
                                      verbose = inp$time)
  em <- joint_dist$fit
  time_taken <- proc.time() - ptm
  # Replace Other column name with FALSE
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
  # Currently disabled.
  # TwoWayAlg(inp)
  if(inp$also_em == TRUE)
    EMAlg(inp)
}

if(!interactive()) {
  main(opts)
}
