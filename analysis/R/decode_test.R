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

library(RUnit)
library(abind)

source('analysis/R/decode.R')
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

MatrixVectorMerge <- function(mat, vec) {
  # Attaches a vector to a matrix, matching corresponding column names

  mat_only <- setdiff(colnames(mat), names(vec))
  vec_only <- setdiff(names(vec), colnames(mat))

  # extend the vector with missing columns
  vec_long <- c(vec, setNames(rep(NA, length(mat_only)), mat_only))

  # extend the matrix with missing columns
  newcols <- matrix(NA, nrow = nrow(mat), ncol = length(vec_only))
  colnames(newcols) <- vec_only
  mat_long <- cbind(mat, newcols)

  # Now vec and mat have the same columns, but in the wrong order. Sort the
  # columns lexicographically.
  if(length(vec_long) > 0) {
    mat_long <- mat_long[, order(colnames(mat_long)), drop = FALSE]
    vec_long <- vec_long[order(names(vec_long))]
  }

  rbind(mat_long, vec_long)
}

RunMultipleTests <- function(title, fun, repetitions, ...) {
  # Run a function with an annotated progress indicator
  cat(title, ": ")

  if(repetitions == 1) {
    # only run once
    fun(...)

    cat(" Done.")
  }
  else {  # run multiple times
    pb <- txtProgressBar(min = 0, max = repetitions,
                         width = getOption("width") - 20 - nchar(title))

    for(i in 1:repetitions) {
      setTxtProgressBar(pb, i)
      fun(...)
    }
    cat(" Done.")
    close(pb)
  }
}

TestEstimatesAndStdsHelper <- function(params, map, pdf, total) {
  # Helper function for TestEstimateBloomCounts.
  partition <- RandomPartition(total, pdf)
  counts <- GenerateCounts(params, map, partition, 1)
  e <- EstimateBloomCounts(params, counts)

  results$estimates <<- abind(results$estimates, e$estimates, along = 3)
  results$stds <<- abind(results$stds, e$stds, along = 3)
}

TestEstimatesAndStds <- function(repetitions, title, params, map, pdf, total) {
  # Checks that the expectations returned by EstimateBloomCounts on simulated
  # inputs match the ground truth and the empirical standard deviation matches
  # EstimateBloomCounts outputs.
  #
  # Input:
  #   repetitions: the number of runs ofEstimateBloomCounts
  #   title: label
  #   params: params vector
  #   map: the map table
  #   pdf: probability density function of the distribution from which simulated
  #        clients are sampled
  #   total: number of reports
  results <<- c(estimates = list(), stds = list())

  RunMultipleTests(title, TestEstimatesAndStdsHelper, repetitions,
                   params, map, pdf, total)

  ave_e <- apply(results$estimates,1:2, mean)
  observed_stds <- apply(results$estimates,1:2, sd)
  ave_stds <- apply(results$stds,1:2, mean)

  ground_truth <- matrix(map %*% pdf, nrow = params$m, byrow = TRUE)

  checkTrue(!any(abs(ave_e - ground_truth) > 1E-9 +  # tolerance level
                                             (ave_stds / repetitions^.5) * 5),
              "Averages deviate too much from expectations.")

  checkTrue(!any(observed_stds > ave_stds * (1 + 5 * repetitions^.5)),
            "Expected standard deviations are too high")

  checkTrue(!any(observed_stds < ave_stds * (1 - 5 * repetitions^.5)),
            "Expected standard deviations are too low")
}

TestEstimateBloomCounts <- function() {
  # Unit tests for the EstimateBloomCounts function.

  report4x2 <- list(k = 4, m = 2)  # 2 cohorts, 4 bits each
  map0 <- Matrix(0, nrow = 8, ncol = 3, sparse = TRUE)  # 3 possible values
  map0[1,] <- c(1, 0, 0)
  map0[2,] <- c(0, 1, 0)
  map0[3,] <- c(0, 0, 1)
  map0[4,] <- c(1, 1, 1)  # 4th bit of the first cohort gets signal from all
  map0[5,] <- c(0, 0, 1)  # 1st bit of the second cohort gets signal from v3

  colnames(map0) <- c('v1', 'v2', 'v3')

  pdf0 <- c(1/2, 1/3, 1/6)
  names(pdf0) <- colnames(map0)

  noise0 <- list(p = 0, q = 1, f = 0)  # no noise at all

  TestEstimatesAndStds(repetitions = 1000, "Testing estimates and stds (1/3)",
                       c(report4x2, noise0), map0, pdf0, 100)

  noise1 <- list(p = 0.4, q = .6, f = 0.5)
  TestEstimatesAndStds(repetitions = 1000, "Testing estimates and stds (2/3)",
                       c(report4x2, noise1), map0, pdf0, 100)

  # MEDIUM TEST: 100 values, 32 cohorts, 8 bits each, 10^6 reports
  values <- 100

  report8x32 <- list(k = 8, m = 32)  # 32 cohorts, 8 bits each

  map1 <- matrix(rbinom(32 * 8 * values, 1, .25), nrow = 32 * 8, ncol = values)

  colnames(map1) <- sprintf("v%d", 1:values)

  pdf1 <- ComputePdf("zipf1", values)

  TestEstimatesAndStds(repetitions = 100, "Testing estimates and stds (3/3)",
                       c(report8x32, noise1), map1, pdf1, 10^9)
}

TestDecodeHelper <- function(params, map, pdf, num_clients,
                             tolerance_l1, tolerance_linf) {
  # Helper function for TestDecode. Simulates a RAPPOR run and checks results of
  # Decode's output against the ground truth. Results are appended to a global
  # list.

  partition <- RandomPartition(num_clients, pdf)
  counts <- GenerateCounts(params, map, partition, 1)
  total <- sum(partition)

  decoded <- Decode(counts, map, params)

  decoded_partition <- setNames(decoded$fit$estimate, decoded$fit$strings)

  results$estimates <<- MatrixVectorMerge(results$estimates, decoded_partition)
  results$stds <<- MatrixVectorMerge(results$stds,
                                          setNames(decoded$fit$std_dev,
                                                   decoded$fit$strings))

  checkTrue(L1Distance(decoded_partition, partition) < total^.5 * tolerance_l1,
            "L1 distance is too large")

  checkTrue(LInfDistance(decoded_partition, partition) <
              max(partition)^.5 * tolerance_linf, "L_inf distance is too large")
}

TestDecodeAveAndStds <- function(...) {
  # Runs Decode multiple times (specified by the repetition argument), checks
  # individuals runs against the ground truth, and the estimates of the standard
  # error against empirical observations.

  results <<- list(estimates = matrix(nrow = 0, ncol = 0),
                   stds = matrix(nrow = 0, ncol = 0))

  RunMultipleTests(...)

  empirical_stds <- apply(results$estimates, 2, sd, na.rm = TRUE)
  estimated_stds <- apply(results$stds, 2, mean, na.rm = TRUE)

  if(dim(results$estimates)[1] > 1)
  {
    checkTrue(any(estimated_stds > empirical_stds / 2),
              "Our estimate for the standard deviation is too low")

    checkTrue(any(estimated_stds < empirical_stds * 3),
              "Our estimate for the standard deviation is too high")
  }
}

TestDecode <- function() {
  # Unit tests for the Decode function.

  # TOY TESTS: three values, 2 cohorts, 4 bits each

  report4x2 <- list(k = 4, m = 2, h = 2)  # 2 cohorts, 4 bits each
  map0 <- Matrix(0, nrow = 8, ncol = 3, sparse = TRUE)  # 3 possible values
  map0[1,] <- c(1, 0, 0)
  map0[2,] <- c(0, 1, 0)
  map0[3,] <- c(0, 0, 1)
  map0[4,] <- c(1, 1, 1)  # 4th bit of the first cohort gets signal from all
  map0[5,] <- c(0, 0, 1)  # 1st bit of the second cohort gets signal from v3

  colnames(map0) <- c('v1', 'v2', 'v3')
  distribution0 <- setNames(c(1/2, 1/3, 1/6),  colnames(map0))

  # Even in the absence of noise, the inferred counts won't necessarily
  # match the ground truth. Must be close enough though.
  noise0 <- list(p = 0, q = 1, f = 0)  # no noise whatsoever

  TestDecodeAveAndStds("Testing Decode (1/5)", TestDecodeHelper, 100,
                       c(report4x2, noise0), map0, distribution0, 100,
                       tolerance_l1 = 5,
                       tolerance_linf = 3)

  noise1 <- list(p = .4, q = .6, f = .5)  # substantial noise, very few reports
  TestDecodeAveAndStds("Testing Decode (2/5)", TestDecodeHelper, 100,
                       c(report4x2, noise1), map0, distribution0, 100,
                       tolerance_l1 = 20,
                       tolerance_linf = 20)

  # substantial noise, many reports
  TestDecodeAveAndStds("Testing Decode (3/5)", TestDecodeHelper, 100,
                       c(report4x2, noise1), map0, distribution0, 100000,
                       tolerance_l1 = 50,
                       tolerance_linf = 40)

  # MEDIUM TEST: 100 values, 32 cohorts, 8 bits each, 10^6 reports
  values <- 100

  report8x32 <- list(k = 8, m = 32, h = 2)  # 32 cohorts, 8 bits each

  map1 <- matrix(rbinom(32 * 8 * values, 1, .25), nrow = 32 * 8, ncol = values)

  colnames(map1) <- sprintf("v%d", 1:values)

  distribution1 <- ComputePdf("zipf1", values)
  names(distribution1) <- colnames(map1)
  TestDecodeAveAndStds("Testing Decode (4/5)", TestDecodeHelper, 100,
                   c(report8x32, noise1), map1, distribution1, 10^6,
                   tolerance_l1 = values * 3,
                   tolerance_linf = 100)

  # Testing LASSO: 500 values, 32 cohorts, 8 bits each, 10^6 reports
  values <- 500

  report8x32 <- list(k = 8, m = 32, h = 2)  # 32 cohorts, 8 bits each

  map2 <- matrix(rbinom(32 * 8 * values, 1, .25), nrow = 32 * 8, ncol = values)

  colnames(map2) <- sprintf("v%d", 1:values)

  distribution2 <- ComputePdf("zipf1.5", values)
  names(distribution2) <- colnames(map2)

  TestDecodeAveAndStds("Testing Decode (5/5)", TestDecodeHelper, 1,
                   c(report8x32, noise0), map2, distribution2, 10^6,
                   tolerance_l1 = values * 3,
                   tolerance_linf = 20)

}

TestAll <- function() {
  TestEstimateBloomCounts()
  TestDecode()
}

TestAll()