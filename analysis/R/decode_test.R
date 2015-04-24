# Copyright 2014 Google Inc. All rights reserved.
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
# This library implements the RAPPOR marginal decoding algorithms using LASSO.

library(RUnit)
library(abind)

source('tests/gen_counts.R')

L1Distance <- function(X, Y) {
  # Computes the L1 distance between two named vectors
  common <- intersect(names(X), names(Y))
  union <- rbind(X[common], Y[common])

  (sum(abs(union[1,]-union[2,])) + sum(X[!names(X) %in% common])
                                 + sum(Y[!names(Y) %in% common])) / 2
}

LInfDistance <- function(X, Y) {
  # Computes the L1 distance between two named vectors
  common <- intersect(names(X), names(Y))
  union <- rbind(X[common], Y[common])

  max(abs(union[1,]-union[2,]),
      X[!names(X) %in% common],
      Y[!names(Y) %in% common])
}


RunMultipleTests <- function(title, fun, repetitions, ...)
{
  cat(title, ": ")
  pb <- txtProgressBar(min = 0, max = repetitions,
                       width = getOption("width") - 20 - nchar(title))

  for(i in 1:repetitions)
  {
    setTxtProgressBar(pb, i)

    fun(...)
  }
  cat(" Done.")

  close(pb)
}

TestEstimatesAndStdsHelper <- function(params, map, partition) {
  # Helper function for TestEstimateBloomCounts.
  counts <- GenerateCounts(params, map, partition, 1)
  e <- EstimateBloomCounts(params, counts)

  results$estimates <<- abind(results$estimates, e$estimates, along = 3)
  results$stds <<- abind(results$stds, e$stds, along = 3)
}

TestEstimatesAndStds <- function(repetitions, title,
                                 params, map, partition, true_distr) {
  v <- 1  # only handly one report per client

  total <- sum(partition)

  results <<- c(estimates = list(), stds = list())

  RunMultipleTests(title, TestEstimatesAndStdsHelper, repetitions,
                   params, map, partition)

  ave_e <- apply(results$estimates,1:2, mean)
  observed_stds <- apply(results$estimates,1:2, sd)
  ave_stds <- apply(results$stds,1:2, mean)

  if(!is.null(true_distr))
    checkTrue(!any((ave_e - true_distr) > (ave_stds / repetitions^.5) * 5),
              "Averages deviate too much from expectations.")

  checkTrue(!any(observed_stds > ave_stds * 2),
            "Expected standard deviations are too pessimistic.")

  checkTrue(!any(observed_stds < ave_stds / 2),
            "Expected standard deviations are too optimistic")
}

TestEstimateBloomCounts <- function() {
  report4x2 <- list(k = 4, m = 2)  # 2 cohorts, 4 bits each
  map0 <- Matrix(0, nrow = 8, ncol = 3, sparse = TRUE)  # 3 possible values
  map0[1,] <- c(1, 0, 0)
  map0[2,] <- c(0, 1, 0)
  map0[3,] <- c(0, 0, 1)
  map0[4,] <- c(1, 1, 1)  # 4th bit of the first cohort gets signal from all
  map0[5,] <- c(0, 0, 1)  # 1st bit of the second cohort gets signal from v3

  colnames(map0) <- c('v1', 'v2', 'v3')

  partition0 <- c(3, 2, 1) * 1000
  names(partition0) <- colnames(map0)

  true_distr <- matrix(c(1/2, 1/3, 1/6, 1, 1/6, 0, 0, 0), 2, 4, byrow = TRUE)

  noise0 <- list(p = 0, q = 1, f = 0)  # no noise at all

  TestEstimatesAndStds(repetitions = 1000, "Testing estimates and stds (1/3)",
                       c(report4x2, noise0), map0, partition0, true_distr)

  noise1 <- list(p = 0.4, q = .6, f = 0.5)
  TestEstimatesAndStds(repetitions = 1000, "Testing estimates and stds (2/3)",
                       c(report4x2, noise1), map0, partition0, true_distr)

  # MEDIUM TEST: 100 values, 32 cohorts, 8 bits each, 10^6 reports
  values <- 100

  report8x32 <- list(k = 8, m = 32)  # 32 cohorts, 8 bits each

  map1 <- matrix(rbinom(32 * 8 * values, 1, .25), nrow = 32 * 8, ncol = values)

  colnames(map1) <- sprintf("v%d", 1:values)

  pdf <- ComputePdf("zipf1", values)
  partition1 <- RandomPartition(10^6, pdf)

  TestEstimatesAndStds(repetitions = 100, "Testing estimates and stds (3/3)",
                       c(report8x32, noise1), map1, partition1, NULL)
}

TestDecodeHelper <- function(params, map, partition, tolerance_l1,
                             tolerance_linf) {
  # Helper function for TestDecode.

  counts <- GenerateCounts(params, map, partition, 1)
  total <- sum(partition)

  decoded <- Decode(counts, map, params)

  l1 <- L1Distance(setNames(decoded$fit$estimate, decoded$fit$strings),
                   partition)

  checkTrue(L1Distance(setNames(decoded$fit$estimate, decoded$fit$strings),
                       partition) < total^.5 * tolerance_l1,
            "L1 distance is too large")

  checkTrue(LInfDistance(setNames(decoded$fit$estimate, decoded$fit$strings),
                       partition) < max(partition)^.5 * tolerance_linf,
            "L_inf distance is too large")
}

TestDecode <- function() {
  report4x2 <- list(k = 4, m = 2, h = 2)  # 2 cohorts, 4 bits each
  map0 <- Matrix(0, nrow = 8, ncol = 3, sparse = TRUE)  # 3 possible values
  map0[1,] <- c(1, 0, 0)
  map0[2,] <- c(0, 1, 0)
  map0[3,] <- c(0, 0, 1)
  map0[4,] <- c(1, 1, 1)  # 4th bit of the first cohort gets signal from all
  map0[5,] <- c(0, 0, 1)  # 1st bit of the second cohort gets signal from v3

  colnames(map0) <- c('v1', 'v2', 'v3')

  # toy example
  partition0 <- setNames(c(3, 2, 1) * 10,  colnames(map0))

  noise0 <- list(p = 0, q = 1, f = 0)  # no noise whatsoever
  # Even in the absence of noise, the inferred counts won't necessarily
  # match the ground truth. Must be close enough though.

  RunMultipleTests("Testing Decode (1/5)", TestDecodeHelper, 100,
                   c(report4x2, noise0), map0, partition0,
                   tolerance_l1 = 5,
                   tolerance_linf = 3)

  noise1 <- list(p = .4, q = .6, f = .5)  # substantial noise
  RunMultipleTests("Testing Decode (2/5)", TestDecodeHelper, 100,
                   c(report4x2, noise1), map0, partition0,
                   tolerance_l1 = 20,
                   tolerance_linf = 10)

  partition1 <- setNames(c(3, 2, 1) * 100000,  colnames(map0))  # many reports
  RunMultipleTests("Testing Decode (3/5)", TestDecodeHelper, 100,
                   c(report4x2, noise1), map0, partition1,
                   tolerance_l1 = 50,
                   tolerance_linf = 40)

  # MEDIUM TEST: 100 values, 32 cohorts, 8 bits each, 10^6 reports
  values <- 100

  report8x32 <- list(k = 8, m = 32, h = 2)  # 32 cohorts, 8 bits each

  map1 <- matrix(rbinom(32 * 8 * values, 1, .25), nrow = 32 * 8, ncol = values)

  colnames(map1) <- sprintf("v%d", 1:values)

  pdf <- ComputePdf("zipf1", values)
  partition1 <- setNames(RandomPartition(10^6, pdf), colnames(map1))
  RunMultipleTests("Testing Decode (4/5)", TestDecodeHelper, 100,
                   c(report8x32, noise1), map1, partition1,
                   tolerance_l1 = values * 3,
                   tolerance_linf = 50)

  # Testing LASSO: 500 values, 32 cohorts, 8 bits each, 10^6 reports
  values <- 500

  report8x32 <- list(k = 8, m = 32, h = 2)  # 32 cohorts, 8 bits each

  map1 <- matrix(rbinom(32 * 8 * values, 1, .25), nrow = 32 * 8, ncol = values)

  colnames(map1) <- sprintf("v%d", 1:values)

  pdf <- ComputePdf("zipf1.5", values)
  partition1 <- setNames(RandomPartition(10^6, pdf), colnames(map1))
  RunMultipleTests("Testing Decode (5/5)", TestDecodeHelper, 100,
                   c(report8x32, noise0), map1, partition1,
                   tolerance_l1 = values * 3,
                   tolerance_linf = 20)

}

TestAll <- function() {
#  TestEstimateBloomCounts()
  TestDecode()
}


TestAll()
