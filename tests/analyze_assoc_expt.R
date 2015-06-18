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
source("tests/gen_counts.R")

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
  # Encoding (var1, var2) \in {(0, 0), (0, 1), (1, 0), (1, 1)}
  two_bits <- list(c(0, 0, 0, 1), c(0, 1, 0, 0), c(0, 0, 1, 0), c(1, 0, 0, 0))
  OuterProd <- function(x, y) {
    as.vector(outer(x, y,
                    function(z, t) z + 2 * t))
  }
  # "report1-major" order
  creports <- mapply(OuterProd, reports2, reports1,
                     SIMPLIFY = FALSE)
  # Collapse counts to bit vector according to two_bits
  lapply(creports,
         function(x) as.vector(sapply(x, function(z) two_bits[[z+1]])))
}


# Given 2 lists of maps, maps1 and maps2, the function
# combines the maps by cohort and outputs both
# cohort-organized maps and flattened versions
CombineMaps <- function(maps1, maps2) {
  # Combine maps
  cmap <- mapply(CombineMapsInternal, maps1, maps2)
  
  # Flatten map
  inds <- lapply(cmap, function(x) which(x, arr.ind = TRUE))
  for (i in seq(1, length(inds))) {
    inds[[i]][, 1] <- inds[[i]][, 1] + (i-1) * dim(cmap[[1]])[1]
  }
  inds <- do.call("rbind", inds)
  crmap <- sparseMatrix(inds[, 1], inds[, 2], dims = c(
    nrow(cmap[[1]]) * length(cmap),
    ncol(cmap[[1]])))
  colnames(crmap) <- colnames(cmap[[1]])
  list(cmap = cmap, crmap = crmap)
}

# Function to combine maps
# Using map1-major order for both candidates and bits of the report
# to be consistent with how CombineReports works
# Currently assume 2-way marginals
CombineMapsInternal <- function(map1, map2) {
  # Retrieve set indices and dimensions
  rows1 <- which(map1, arr.ind = TRUE)[,1]
  cols1 <- which(map1, arr.ind = TRUE)[,2]
  length1 <- dim(map1)[[1]]
  width1 <- dim(map1)[[2]]
  rows2 <- which(map2, arr.ind = TRUE)[,1]
  cols2 <- which(map2, arr.ind = TRUE)[,2]
  length2 <- dim(map2)[[1]]
  width2 <- dim(map2)[[2]]
  
  # Now process map1
  map1fn <- function(i, j) {
    i1 <- seq(1, length2) + ((i-1) * length2)
    j1 <- seq(1, width2) + ((j-1) * width2)
    expand.grid(i1, j1)  
  }
  map1indices <- do.call(rbind,
                         mapply(map1fn, rows1, cols1, SIMPLIFY = FALSE))
  map1_big <- sparseMatrix(map1indices[,"Var1"],
                           map1indices[,"Var2"],
                           dims = c(length1 * length2,
                                    width1 * width2))
  colnames(map1_big) <- t(outer(colnames(map1),
                              colnames(map2),
                              function(x, y) paste(x, y, sep = "x")))
  
  # Now process map2
  map2fn <- function(i, j) {
    i2 <- i + (seq(0, length1 - 1) * length2)
    j2 <- j + (seq(0, width1 - 1) * width2)
    expand.grid(i2, j2)
  }
  map2indices <- do.call(rbind,
                         mapply(map2fn, rows2, cols2, SIMPLIFY = FALSE))
  map2_big <- sparseMatrix(map2indices[,"Var1"],
                           map2indices[,"Var2"],
                           dims = c(length1 * length2,
                                    width1 * width2))
  colnames(map2_big) <- t(outer(colnames(map1),
                              colnames(map2),
                              function(x, y) paste(x, y, sep = "x")))
  
  # Now collate two maps with entries in (1000, 0100, 0010, 0001)
  # (m1&m2, !m1 & m2, m1 & !m2, !(m1 & m2)) respectively
  findices <- which(map1_big & map2_big, arr.ind = TRUE)
  # 1000
  findices[, 1] <- findices[, 1] * 4 - 3
  # 0100
  indices_0100 <- which((!map1_big) & map2_big, arr.ind = TRUE)
  indices_0100[, 1] <- indices_0100[, 1] * 4 - 2
  findices <- rbind(findices, indices_0100)
  # 0010
  indices_0010 <- which(map1_big & (!map2_big), arr.ind = TRUE)
  indices_0010[, 1] <- indices_0010[, 1] * 4 - 1
  findices <- rbind(findices, indices_0010)
  # 0001
  indices_0001 <- which((!map1_big) & (!map2_big), arr.ind = TRUE)
  indices_0001[, 1] <- indices_0001[, 1] * 4
  findices <- rbind(findices, indices_0001)
  sm <- sparseMatrix(findices[, 1], findices[, 2],
                     dims = c(4 * length1 * length2,
                        width1 * width2))
  colnames(sm) <- colnames(map1_big)
  sm
}


main <- function(opts) {
  ptm <- proc.time()
  direct_simulation = TRUE
  inp <- fromJSON(opts$inp)
  params <- ReadParameterFile(inp$params)
  if(direct_simulation == TRUE) {
    # TWO WAY ASSOCIATIONS; INPUTS SIMULATED DIRECTLY
    strconstant <- c("string", "option")
    N <- inp$num
    n1 <- inp$varcandidates[[1]]
    n2 <- inp$varcandidates[[2]]
    
    # Construct unique vals for each variable using strconstant
    stopifnot(length(strconstant) == inp$numvars)
    uvals <- lapply(1:inp$numvars,
                    function(i) {
                      apply(as.matrix(1:inp$varcandidates[[i]]),
                            1,
                            function(z) sprintf("%s%d", strconstant[[i]], z))
                    })
    
    # Add extras if any
    if(inp$extras > 0) {
      uvals[[1]] <- c(uvals[[1]], apply(as.matrix(1:inp$extras), 1,
                          function(z) sprintf("%s%d", strconstant[[1]], z + n1)))
    }
    
    map <- lapply(uvals, function(u) CreateMap(u, params))
    trim <- function(map) {
      lapply(map, function(z) z[,1:n1])
    }
    # Trim maps to real # of candidates
    # Use extras only for decoding
    tmap <- trim(map[[1]]$map)
    crmap_trimmed <- CombineMaps(tmap, map[[2]]$map)$crmap
    
    # Sample values to compute partition
    # Zipfian over n1 strings
    v1_part <- RandomPartition(N, ComputePdf("zipf1.5", n1))
    # Zipfian over n2 strings for each of variable 1
    # Distr. are correlated as in assoc_sim.R
    final_part <- as.vector(sapply(1:n1,
                    function(i) {
                      v2_part <- RandomPartition(v1_part[[i]],
                                                 ComputePdf("zipf1.5", n2))
                      if (i %% 2 == 0) {v2_part} else {rev(v2_part)}
                    }))
    
    td <- matrix(final_part/sum(final_part), nrow = n1, ncol = n2, byrow = TRUE)
    rownames(td) <- uvals[[1]][1:n1]  # Don't take into account extras
    colnames(td) <- uvals[[2]]
    print(signif(td, 4))
    cohorts <- as.matrix(
      apply(as.data.frame(final_part), 1,
            function(count) RandomPartition(count, rep(1, params$m))))
    expanded <- apply(cohorts, 2, function(vec) rep(vec, each = ((params$k)**2)*4))
    true_ones <- apply(expanded * crmap_trimmed, 1, sum)
    
    p <- params$p
    q <- params$q
    f <- params$f
    m <- params$m
    k <- params$k
    
    p11 <- q * (1 - f/2) + p * f / 2  # probability of a true 1 reported as 1
    p01 <- p * (1 - f/2) + q * f / 2  # probability of a true 0 reported as 1
    p10 <- 1 - p11  # probability of a true 1 reported as 0
    p00 <- 1 - p01  # probability of a true 0 reported as 0
    
    NoiseMatrix <- matrix(rep(0, 16), 4)
    NoiseMatrix[1,] <- c(p11**2, p11*p10, p10*p11, p10**2)
    NoiseMatrix[2,] <- c(p11*p01, p11*p00, p10*p01, p10*p00)
    NoiseMatrix[3,] <- c(p01*p11, p01*p10, p00*p11, p00*p01)
    NoiseMatrix[4,] <- c(p01**2, p00*p01, p01*p00, p00**2)

    after_noise <- as.vector(sapply(1:(length(true_ones)/4), 
                                    function(x) 
                                      t(NoiseMatrix) %*% true_ones[((x-1)*4+1):(x*4)]))
    counts <- cbind(apply(cohorts, 1, sum),
                    matrix(after_noise,
                           nrow = m,
                           ncol = 4 * (k**2),
                           byrow = TRUE))
    params2 <- params
    params2$k <- (params$k ** 2) * 4
    crmap <- CombineMaps(map[[1]]$map, map[[2]]$map)$crmap
    marginal <- Decode2Way(counts, crmap, params2)$fit
    ed <- td
    for (cols in colnames(td)) {
      for (rows in rownames(td)) {
        ed[rows, cols] <- marginal[paste(rows, cols, sep = "x"), "Estimate"]
      }
    }
    
    time_taken <- proc.time() - ptm
    
    print("2 WAY RESULTS")
    print(signif(ed, 4))
    print(l1d(td, ed, "L1 DISTANCE 2 WAY"))
    print("PROC.TIME")
    print(time_taken)
  } else {
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
    # CombineMaps(map[[1]]$map[[1]], map[[2]]$map[[1]])
    cmap <- mapply(CombineMaps, map[[1]]$map, map[[2]]$map)
    # Combine cohorts into one map. Needed for Decode2Way
    inds <- lapply(cmap, function(x) which(x, arr.ind = TRUE))
    for (i in seq(1, length(inds))) {
      inds[[i]][, 1] <- inds[[i]][, 1] + (i-1) * dim(cmap[[1]])[1]
    }
    inds <- do.call("rbind", inds)
    
    # inds[[2]][, 1] <- inds[[2]][, 1] + dim(cmap[[1]])[1]
    # inds <- rbind(inds[[1]], inds[[2]])
    crmap <- sparseMatrix(inds[, 1], inds[, 2], dims = c(
                                                  nrow(cmap[[1]]) * length(cmap),
                                                  ncol(cmap[[1]])))
    td <- read.csv(file = inp$truefile)
    colnames(crmap) <- colnames(cmap[[1]])
    counts <- ComputeCounts(creports, cohorts[[1]], params2)
    marginal <- Decode2Way(counts, crmap, params2)$fit
    
    also_em = FALSE
    ed_em <- list()
    if(also_em == TRUE) {
      joint_dist <- ComputeDistributionEM(reports, cohorts, map,
                                          ignore_other = TRUE,
                                          quick = TRUE,
                                          params, marginals = NULL,
                                          estimate_var = FALSE,
                                          new_alg = inp$newalg)
      ed_em <- joint_dist$orig$fit
      if(length(reports) == 3) {
        ed_em <- as.data.frame(ed_em)
      }
    }
    
    ed <- td
    for (cols in colnames(td)) {
      for (rows in rownames(td)) {
        ed[rows, cols] <- marginal[paste(rows, cols, sep = "x"), "Estimate"]
      }
    }
    
    time_taken <- proc.time() - ptm
    
    print("2 WAY RESULTS")
    print(signif(ed[order(rowSums(ed)), ], 4))
    print(l1d(td, ed, "L1 DISTANCE 2 WAY"))
    print("PROC.TIME")
    print(time_taken)
    
    metrics <- list(
      td_chisq = chisq.test(td)[1][[1]][[1]],
      ed_chisq = chisq.test(ed)[1][[1]][[1]],
      tv = l1d(td, ed, ""),
      time = time_taken[1],
      dim1 = dim(ed)[[2]],
      dim2 = dim(ed)[[1]]
    )
    
    if(also_em == TRUE) {
      # Add EM metrics
      metrics <- c(metrics,
                   list(ed_em_chisq = chisq.test(ed_em)[1][[1]][[1]],
                        tv_em = l1d(td, ed_em, "")/2))
    }
    
    # Write metrics to metrics.csv
    # Report l1 distance / 2 to be consistent with histogram analysis
    filename <- file.path(inp$outdir, 'metrics.csv')
    write.csv(metrics, file = filename, row.names = FALSE)
  }  
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
