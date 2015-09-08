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

#
# This library implements RAPPOR decoding algorithms for 2 way association.
#

library(limSolve)
source("analysis/R/decode.R")


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


EstimateBloomCounts2Way <- function(params, obs_counts) {
  # Estimates original bloom filter counts of each pair of bits
  # in the original bloom filters of each report
  #
  # Input:
  #    params: a list of RAPPOR parameters:
  #            k - size of a Bloom filter
  #            h - number of hash functions
  #            m - number of cohorts
  #            p - P(IRR = 1 | PRR = 0)
  #            q - P(IRR = 1 | PRR = 1)
  #            f - Proportion of bits in the Bloom filter that are set randomly
  #                to 0 or 1 regardless of the underlying true bit value
  #    obs_counts: a matrix of size m by (4k^2 + 1). Column one contains sample
  #                sizes for each cohort. Other counts indicated how many times
  #                pairs of bits {11, 10, 01, 00} were set across the two
  #                reports (in a "1st report"-major order)
  #
  # Output:
  #    ests: a matrix of size m by 4k**2 with estimated counts
  #    stds: currently, just a filler value of 100
  
  p <- params$p
  q <- params$q
  f <- params$f
  m <- params$m
  k <- params$k
  
  stopifnot(m == nrow(obs_counts), params$k + 1 == ncol(obs_counts))
  
  p11 <- q * (1 - f/2) + p * f / 2  # probability of a true 1 reported as 1
  p01 <- p * (1 - f/2) + q * f / 2  # probability of a true 0 reported as 1
  p10 <- 1 - p11  # probability of a true 1 reported as 0
  p00 <- 1 - p01  # probability of a true 0 reported as 0
  
  # The NoiseMatrix describes the probability that input pairs of bits
  # are mapped to outputs {11, 10, 01, 00} due to noise added by RAPPOR
  NoiseMatrix <- matrix(rep(0, 16), 4)
  NoiseMatrix[1,] <- c(p11**2, p11*p10, p10*p11, p10**2)
  NoiseMatrix[2,] <- c(p11*p01, p11*p00, p10*p01, p10*p00)
  NoiseMatrix[3,] <- c(p01*p11, p01*p10, p00*p11, p00*p10)
  NoiseMatrix[4,] <- c(p01**2, p01*p00, p00*p01, p00**2)
  # Invert NoiseMatrix for estimator
  InvNoiseMatrix <- t(solve(NoiseMatrix))
  
  # Apply the inverse of NoiseMatrix to get an unbiased estimator for
  # the number of times input pairs of bits were seen.
  # Apply the matrix to 4 values at a time from obs_counts
  ests <- apply(obs_counts, 1, function(x) {
    N <- x[1]
    inds <- seq(0, (k/4)-1)
    v <- x[-1]
    sapply(inds, function(i){
      as.vector(InvNoiseMatrix %*% v[(i*4 + 1):((i+1)*4)])
    })
  })
  
  # Transform counts from absolute values to fractional, removing bias due to
  #      variability of reporting between cohorts.
  ests <- apply(ests, 1, function(x) x / obs_counts[,1])
  # TODO: compute stddev in distribution induced by estimation
  # stds <- apply(variances^.5, 1, function(x) x / obs_counts[,1])
  
  # Some estimates may be set to infinity, e.g. if f=1. We want to
  #     account for this possibility, and set the corresponding counts
  #     to 0.
  ests[abs(ests) == Inf] <- 0
  
  list(estimates = ests,
       stds = matrix(rep(100, length(ests[,1]) * length(ests[1,])),
                     length(ests[,1])))
}

# Implements lsei
FitDistribution2Way <- function(estimates_stds, map,
                                fit = NULL,
                                quiet = FALSE,
                                add_constraints = FALSE) {
  X <- map
  Y <- as.vector(t(estimates_stds$estimates))
  m <- dim(X)[1]
  n <- dim(X)[2]
  
  G <- rbind2(Diagonal(n), rep(-1, n))
  H <- c(rep(0, n), -1)
  if (add_constraints == TRUE) {
    res <- AddConstraints(fit, X, Y, m, n, G, H)
    lsei(A = res$X, B = res$Y, G = res$G, H = res$H, type = 2)$X
  } else {
    lsei(A = X, B = Y, G = G, H = H, type = 2)$X
  }
}

AddConstraints <- function(fit, X, Y, m, n, G, H) {
  # Experimental code
  # Computes the same output as FitDistribution by 
  # additionally throwing in constraints corresponding to
  # 1-way marginals
  # Requires non-NULL fit as input (with "proportion" containing marginal info)

  X <- cbind2(X, setNames(rep(1, m), "intercept"))
  G <- cbind2(G, rep(0, n+1))
  
  # Adding marginals constraints to X and Y
  wt <- 1
  fstrs <- fit[,"string"] #  found strings
  
  # H <- c(H, -wt * t(fit["prop_high_95"]))
  H <- c(H, -wt * t(fit[,2]))
  
  for (strs in fstrs) {
    indices <- which(colnames(X) %in% outer(strs,
                                    c("FALSE", "TRUE"),
                                    function(x, y) paste(x, y, sep = "x")))
    vec <- rep(0, n + 1)
    vec[indices] <- -wt
    # X <- rbind2(X, vec)
    G <- rbind2(G, vec)
  }
  
  if(FALSE) {
    for (strs in fstrs[[2]]) {
      indices <- which(colnames(X) %in% outer(fstrs[[1]],
                                      strs,
                                      function(x, y) paste(x, y, sep = "x")))
      vec <- rep(0, n)
      vec[indices] <- wt
      X <- rbind2(X, vec)
    }
  }
  list(X = X, Y = Y, G = G, H = H)
} 

Decode2Way <- function(counts, map, params, fit = NULL) {
  k <- params$k
  p <- params$p
  q <- params$q
  f <- params$f
  h <- params$h
  m <- params$m
  
  S <- ncol(map)  # total number of candidates
  
  N <- sum(counts[, 1])
  
  filter_cohorts <- which(counts[, 1] != 0)  # exclude cohorts with zero reports
  
  # stretch cohorts to bits
  filter_bits <- as.vector(
    t(matrix(1:nrow(map), nrow = m, byrow = TRUE)[filter_cohorts,]))
  
  es <- EstimateBloomCounts2Way(params, counts)
  e <- list(estimates = es$estimates[filter_cohorts, , drop = FALSE],
            stds = es$stds[filter_cohorts, , drop = FALSE])
  coefs <- FitDistribution2Way(e, map[filter_bits, , drop = FALSE], fit, add_constraints = TRUE)
  # IS LSEI WORKING?
  X <- map; Y <- as.vector(t(e$estimates));
  m <- dim(X)[1];
  n <- dim(X)[2];
  X <- cbind2(X, setNames(rep(1, m), "intercept"));
  d = X %*% coefs - Y;
  print(sum(d * d))
  
  coefs <- coefs[1:length(coefs)-1]
  fit <- data.frame(String = colnames(map[filter_bits, , drop = FALSE]),
                    Estimate = matrix(coefs, ncol = 1),
                    SD = matrix(coefs, ncol = 1),
                    stringsAsFactors = FALSE)
  rownames(fit) <- fit[,"String"]
  list(fit = fit)
}
