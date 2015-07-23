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
  NoiseMatrix[3,] <- c(p01*p11, p01*p10, p00*p11, p00*p01)
  NoiseMatrix[4,] <- c(p01**2, p00*p01, p01*p00, p00**2)
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
                                quiet = FALSE) {
  X <- map
  Y <- as.vector(t(estimates_stds$estimates))
  m <- dim(X)[1]
  n <- dim(X)[2]
  
  G <- rbind2(Diagonal(n), rep(-1, n))
  H <- c(rep(0, n), -1)
  lsei(A = X, B = Y, G = G, H = H, type = 2)$X
}

FitDistribution2WayAdditionalConstraints <- function(estimates_stds, map, fit) {
  # Experimental code
  # Computes the same output as FitDistribution by 
  # additionally throwing in constraints corresponding to
  # 1-way marginals
  # Requires non-NULL fit as input (with "proportion" containing marginal info)

  X <- as.matrix(map)
  Y <- as.vector(t(estimates_stds$estimates))
  m <- dim(X)[1]
  n <- dim(X)[2]
  wt <- 10000 #  weight to marginal constraints
  
  G <- rbind2(Diagonal(n), rep(-1, n))
  H <- c(rep(0, n), -1)
  
  # Adding marginals constraints to X and Y
  fstrs <- lapply(fit, function(x) x[,"string"]) #  found strings
  
  Y <- c(Y, wt * t(fit[[1]]["proportion"]), wt * t(fit[[2]]["proportion"]))
  
  for (strs in fstrs[[1]]) {
    indices <- which(colnames(map) %in% outer(strs,
                                    fstrs[[2]],
                                    function(x, y) paste(x, y, sep = "x")))
    vec <- rep(0, n)
    vec[indices] <- wt
    X <- rbind2(X, vec)
  }
  for (strs in fstrs[[2]]) {
    indices <- which(colnames(map) %in% outer(fstrs[[1]],
                                    strs,
                                    function(x, y) paste(x, y, sep = "x")))
    vec <- rep(0, n)
    vec[indices] <- wt
    X <- rbind2(X, vec)
  }
  
  lsei(A = X, B = Y, G = G, H = H, type = 2)$X
  
  # Random projection params
  #   size <- 10 * n
  #   density <- 0.05
  #   rproj <- matrix(0, size, m)
  #   rproj[sample(length(rproj), size = density * length(rproj))] <- rnorm(density * length(rproj))
  #   # rproj <- matrix(rnorm(10*n*m), 10*n, m)
  #   Xproj <- rproj %*% X
  #   Yproj <- as.vector(rproj %*% Y)
  #   mproj <- dim(Xproj)[1]
  #   nproj <- dim(Xproj)[2]
  #   
  #   G <- rbind2(Diagonal(nproj), rep(-1, nproj))
  #   H <- c(rep(0, nproj), -1)
  #   lsei(A = Xproj, B = Yproj, G = G, H = H, type = 2)$X
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
  coefs <- FitDistribution2Way(e, map[filter_bits, , drop = FALSE], fit)
  fit <- data.frame(String = colnames(map[filter_bits, , drop = FALSE]),
                    Estimate = matrix(coefs, ncol = 1),
                    SD = matrix(coefs, ncol = 1),
                    stringsAsFactors = FALSE)
  rownames(fit) <- fit[,"String"]
  list(fit = fit)
}
