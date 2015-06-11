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
#       $ ./analyze_assoc_expt.R --inp <input JSON file>
#
# Input file: 
# Outputs:

library("jsonlite")
library("optparse")

options(stringsAsFactors = FALSE)

if(!interactive()) {
  option_list <- list(
    make_option(c("--inp"), default = "analyze_inp.json",
                help = "JSON file with inputs for analyze_assoc_expt"))
  opts <- parse_args(OptionParser(option_list = option_list))
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
  map$rmap <- map$map
  map$map <- lapply(1:params$m, function(i)
                          map$rmap[seq(from = ((i - 1) * params$k + 1),
                                   length.out = params$k),])
  map
}

# Function to combine reports
# Currently assume 2-way marginals
CombineReports <- function(reports1, reports2) {
  two_bits <- list(c(0, 0, 0, 1), c(0, 0, 1, 0), c(0, 1, 0, 0), c(1, 0, 0, 0))
  OuterProd <- function(x, y) {
    as.vector(outer(x, y,
                    function(z, t) z + 2 * t))
  }
  creports <- mapply(OuterProd, reports1, reports2,
                     SIMPLIFY = FALSE)
  # Collapse counts to bit vector according to two_bits
  lapply(creports,
         function(x) as.vector(sapply(x, function(z) two_bits[[z+1]])))
}

# Function to combine maps
# Using map1-major order for both candidates and bits of the report
# to be consistent with how CombineReports works
# Currently assume 2-way marginals
CombineMaps <- function(map1, map2) {
  # Retrieve set indices and dimensions
  rows1 <- which(map1, arr.ind = TRUE)[,1]
  cols1 <- which(map1, arr.ind = TRUE)[,2]
  length1 <- dim(map1)[[1]]
  width1 <- dim(map1)[[2]]
  rows2 <- which(map2, arr.ind = TRUE)[,1]
  cols2 <- which(map2, arr.ind = TRUE)[,2]
  length2 <- dim(map2)[[1]]
  width2 <- dim(map2)[[2]]
  
  map1fn <- function(i, j) {
    i1 <- seq(1, length2) + (i-1) * length2
    j1 <- seq(1, width2) + (j-1) * width2
    indices1 <- expand.grid(i1, j1)
  }
  map1indices <- do.call(rbind,
                         mapply(map1fn, rows1, cols1, SIMPLIFY = FALSE))
  map1_big <- sparseMatrix(map1indices[,"Var1"],
                           map1indices[,"var2"],
                           dims = c(length1 * length2,
                                    width1 * width2))
  colnames(map1_big) <- outer(function(x, y) paste(x, y, sep = "x"),
                              colnames(map1),
                              colnames(map2))
}


main <- function(opts) {
  ptm <- proc.time()
  inp <- fromJSON(opts$inp)
  params <- ReadParameterFile(inp$params)
  # ensure sufficient maps as required by number of vars
  stopifnot(inp$numvars == length(inp$maps))
  opts_map <- inp$maps
  map <- lapply(opts_map, function(o)
                  ProcessMap(ReadMapFile(o, params = params),
                             params = params))
  # Reports must be of the format
  #     cohort no, rappor bitstring 1, rappor bitstring 2, ...
  reportsObj <- read.csv(inp$reports,
                         colClasses = c("integer",
                                        rep("character", inp$numvars)),
                         header = FALSE)

  # Parsing reportsObj
  # ComputeDistributionEM allows for different sets of cohorts
  # for each variable. Here, both sets of cohorts are identical
  co <- as.list(reportsObj[1])[[1]]
  cohorts <- rep(list(co), inp$numvars)
  # Parse reports from reportObj cols 2, 3, ...
  reports <- lapply(1:inp$numvars, function(x) as.list(reportsObj[x + 1]))

  # Split strings into bit arrays (as required by assoc analysis)
  reports <- lapply(1:inp$numvars, function(i) {
    # apply the following function to each of reports[[1]] and reports[[2]]
    lapply(reports[[i]][[1]], function(x) {
      # function splits strings and converts them to numeric values
      as.numeric(strsplit(x, split = "")[[1]])
    })
  })

  creports <- CombineReports(reports[[1]], reports[[2]])
  params2 <- params
  params2$k <- (params$k ** 2) * 4
  CombineMaps(map[[1]]$map[[1]], map[[2]]$map[[1]])
  cmap <- mapply(CombineMaps, map[[1]]$map, map[[2]]$map)
  counts <- ComputeCounts(creports, cohorts[[1]], params2)
  
  
  return
  joint_dist <- ComputeDistributionEM(reports, cohorts, map,
                                      ignore_other = TRUE,
                                      quick = TRUE,
                                      params, marginals = NULL,
                                      estimate_var = FALSE,
                                      new_alg = inp$newalg)

  
  td <- read.csv(file = inp$truefile)
  ed <- joint_dist$orig$fit
  if(length(reports) == 3) {
    ed <- as.data.frame(ed) 
  }
  
  # We can see if chi-squared tests show different results
  # for estimated vs real distribution
  print("CHI-SQUARED")
  td_chisq <- chisq.test(td)
  ed_chisq <- chisq.test(ed)
  print(td_chisq)
  print(ed_chisq)
  print(l1d(td, ed, "L1 DISTANCE"))
  l1d_metric <- l1d(td, ed, "")
  print("JOINT_DIST$FIT")
  print(signif(ed[order(rowSums(ed)),], 4))
  td_metric <- td_chisq[1][[1]][[1]]
  ed_metric <- ed_chisq[1][[1]][[1]]
  
  print("PROC.TIME")
  time_taken <- proc.time() - ptm
  print(time_taken)
  
  metrics <- list(td_chisq = td_metric,
                  ed_chisq = ed_metric,
                  tv = l1d_metric/2,
                  time = time_taken[1],
                  dim1 = dim(ed)[[2]],
                  dim2 = dim(ed)[[1]])
  
  # Write metrics to metrics.csv
  # Report l1 distance / 2 to be consistent with histogram analysis
  filename <- file.path(inp$outdir, 'metrics.csv')
  write.csv(metrics, file = filename, row.names = FALSE)
}

# L1 distance = 1 - sum(min(df1|x, df2|x)) where
# df1|x / df2|x projects the distribution to the intersection x of the
# supports of df1 and df2
l1d <- function(df1, df2, statement = "L1 DISTANCE") {
  rowsi <- intersect(rownames(df1), rownames(df2))
  colsi <- intersect(colnames(df1), colnames(df2))
  print(statement)
  1 - sum(mapply(min, 
                 unlist(as.data.frame(df1)[rowsi, colsi], use.names = FALSE),
                 unlist(as.data.frame(df2)[rowsi, colsi], use.names = FALSE)))
}

if(!interactive()) {
  main(opts)
}
