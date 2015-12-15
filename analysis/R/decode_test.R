#!/usr/bin/Rscript
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

  L1_intersect <- sum(abs(X[common] - Y[common]))
  L1_X_minus_Y <- sum(X[!names(X) %in% common])
  L1_Y_minus_X <- sum(Y[!names(Y) %in% common])

  (L1_intersect + L1_X_minus_Y + L1_Y_minus_X) / 2
}

LInfDistance <- function(X, Y) {
  # Computes the L_infinity distance between two named vectors
  common <- intersect(names(X), names(Y))

  max(abs(X[common] - Y[common]),
      abs(X[!names(X) %in% common]),
      abs(Y[!names(Y) %in% common]))
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
  # Run a function with an annotated progress indicator. The function's outputs
  # are concatenated and returned as a list of length repetitions.
  cat(title, ": ")

  if(repetitions == 1) {
    # only run once
    results <- list(fun(...))

    cat(" Done.\n")
  } else {  # run multiple times
    pb <- txtProgressBar(min = 0, max = repetitions,
                         width = getOption("width") - 20 - nchar(title))

    results <- vector(mode = "list", repetitions)
    for(i in 1:repetitions) {
      setTxtProgressBar(pb, i)
      results[[i]] <- fun(...)
    }
    cat(" Done.")
    close(pb)
  }

  results
}

CheckEstimatesAndStdsHelper <- function(params, map, pdf, total) {
  # Helper function for TestEstimateBloomCounts.
  partition <- RandomPartition(total, pdf)
  counts <- GenerateCounts(params, map, partition, 1)

  EstimateBloomCounts(params, counts)
}

CheckEstimatesAndStds <- function(repetitions, title, params, map, pdf, total) {
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

  results <- RunMultipleTests(title, CheckEstimatesAndStdsHelper, repetitions,
                              params, map, pdf, total)

  estimates <- abind(lapply(results, function(r) r$estimates), along = 3)
  stds <- abind(lapply(results, function(r) r$stds), along = 3)

  ave_e <- apply(estimates, 1:2, mean)
  observed_stds <- apply(estimates, 1:2, sd)
  ave_stds <- apply(stds, 1:2, mean)

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

  CheckEstimatesAndStds(repetitions = 1000, "Testing estimates and stds (1/3)",
                        c(report4x2, noise0), map0, pdf0, 100)

  noise1 <- list(p = 0.4, q = .6, f = 0.5)
  CheckEstimatesAndStds(repetitions = 1000, "Testing estimates and stds (2/3)",
                        c(report4x2, noise1), map0, pdf0, 100)

  # MEDIUM TEST: 100 values, 32 cohorts, 8 bits each, 10^6 reports
  values <- 100

  report8x32 <- list(k = 8, m = 32)  # 32 cohorts, 8 bits each

  map1 <- matrix(rbinom(32 * 8 * values, 1, .25), nrow = 32 * 8, ncol = values)

  colnames(map1) <- sprintf("v%d", 1:values)

  pdf1 <- ComputePdf("zipf1", values)

  CheckEstimatesAndStds(repetitions = 100, "Testing estimates and stds (3/3)",
                        c(report8x32, noise1), map1, pdf1, 10^9)
}

CheckDecodeHelper <- function(params, map, pdf, num_clients,
                             tolerance_l1, tolerance_linf) {
  # Helper function for TestDecode. Simulates a RAPPOR run and checks results of
  # Decode's output against the ground truth. Output is returned as a list.

  partition <- RandomPartition(num_clients, pdf)
  counts <- GenerateCounts(params, map, partition, 1)
  total <- sum(partition)

  decoded <- Decode(counts, map, params, quiet = TRUE)

  decoded_partition <- setNames(decoded$fit$estimate, decoded$fit$string)

  checkTrue(L1Distance(decoded_partition, partition) < total^.5 * tolerance_l1,
            sprintf("L1 distance is too large: \
                    L1Distance = %f, total^0.5 * tolerance_l1 = %f",
                    L1Distance(decoded_partition, partition),
                    total^0.5 * tolerance_l1))

  checkTrue(LInfDistance(decoded_partition, partition) <
              max(partition)^.5 * tolerance_linf,
              sprintf("L_inf distance is too large: \
                      L1Distance = %f, max(partition)^0.5 * tolerance_linf = %f",
                      L1Distance(decoded_partition, partition),
                      max(partition)^0.5 * tolerance_linf))

  list(estimates = decoded_partition,
       stds = setNames(decoded$fit$std_error, decoded$fit$string))
}

CheckDecodeAveAndStds <- function(...) {
  # Runs Decode multiple times (specified by the repetition argument), checks
  # individuals runs against the ground truth, and the estimates of the standard
  # error against empirical observations.

  results <- RunMultipleTests(...)

  estimates <- matrix(nrow = 0, ncol = 0)
  lapply(results, function(r) MatrixVectorMerge(estimates, r$estimates))

  stds <- matrix(nrow = 0, ncol = 0)
  lapply(results, function(r) MatrixVectorMerge(stds, r$stds))

  empirical_stds <- apply(estimates, 2, sd, na.rm = TRUE)
  estimated_stds <- apply(stds, 2, mean, na.rm = TRUE)

  if(dim(estimates)[1] > 1) {
    checkTrue(any(estimated_stds > empirical_stds / 2),
              "Our estimate for the standard deviation is too low")

    checkTrue(any(estimated_stds < empirical_stds * 3),
              "Our estimate for the standard deviation is too high")
  }
}

TestDecode <- function() {
  # Unit tests for the Decode function.

  # TOY TESTS: three values, 2 cohorts, 4 bits each

  params_4x2 <- list(k = 4, m = 2, h = 2)  # 2 cohorts, 4 bits each
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

  # Args are: message str, test function, # repetitions,
  #           params, map, true pdf, # clients,
  #           tolerances
  CheckDecodeAveAndStds("Testing Decode (1/5)", CheckDecodeHelper, 100,
                        c(params_4x2, noise0), map0, distribution0, 100,
                        tolerance_l1 = 5,
                        tolerance_linf = 3)

  noise1 <- list(p = .4, q = .6, f = .5)  # substantial noise, very few reports
  CheckDecodeAveAndStds("Testing Decode (2/5)", CheckDecodeHelper, 100,
                        c(params_4x2, noise1), map0, distribution0, 100,
                        tolerance_l1 = 20,
                        tolerance_linf = 20)

  # substantial noise, many reports
  CheckDecodeAveAndStds("Testing Decode (3/5)", CheckDecodeHelper, 100,
                        c(params_4x2, noise1), map0, distribution0, 100000,
                        tolerance_l1 = 50,
                        tolerance_linf = 40)

  # MEDIUM TEST: 100 values, 32 cohorts, 8 bits each, 10^6 reports
  num_values <- 100

  params_8x32 <- list(k = 8, m = 32, h = 2)  # 32 cohorts, 8 bits each

  map1 <- matrix(rbinom(32 * 8 * num_values, 1, .25), nrow = 32 * 8, ncol =
                 num_values)

  colnames(map1) <- sprintf("v%d", 1:num_values)

  distribution1 <- ComputePdf("zipf1", num_values)
  names(distribution1) <- colnames(map1)
  CheckDecodeAveAndStds("Testing Decode (4/5)", CheckDecodeHelper, 100,
                        c(params_8x32, noise1), map1, distribution1, 10^6,
                        tolerance_l1 = num_values * 3,
                        tolerance_linf = 100)

  # Testing LASSO: 500 values, 32 cohorts, 8 bits each, 10^6 reports
  num_values <- 500

  params_8x32 <- list(k = 8, m = 32, h = 2)  # 32 cohorts, 8 bits each

  map2 <- matrix(rbinom(32 * 8 * num_values, 1, .25), nrow = 32 * 8, ncol =
                 num_values)

  colnames(map2) <- sprintf("v%d", 1:num_values)

  distribution2 <- ComputePdf("zipf1.5", num_values)
  names(distribution2) <- colnames(map2)

  CheckDecodeAveAndStds("Testing Decode (5/5)", CheckDecodeHelper, 1,
                        c(params_8x32, noise1), map2, distribution2, 10^6,
                        tolerance_l1 = num_values * 3,
                        tolerance_linf = 80)

}

TestDecodeBool <- function() {
  # Testing Boolean Decode
  num_values <- 2
  # 1 bit; rest of the params don't matter
  params_bool <- list(k = 1, m = 128, h = 2)
  # setting up map_bool to be consistent with the Decode API and for
  # GenerateCounts()
  map_bool <- matrix(c(0, 1), nrow = 128 * 1, ncol = num_values, byrow = TRUE)

  colnames(map_bool) <- c("FALSE", "TRUE")
  distribution_bool <- ComputePdf("zipf1.5", num_values)
  names(distribution_bool) <- colnames(map_bool)
  noise2 <- list(p = 0.25, q = 0.75, f = 0.5)

  # tolerance_l1 set to four standard deviations to avoid any flakiness in
  # tests
  CheckDecodeAveAndStds("Testing .DecodeBoolean (1/3)", CheckDecodeHelper, 100,
                        c(params_bool, noise2), map_bool, distribution_bool,
                        10^6,
                        tolerance_l1 = 4 * num_values,
                        tolerance_linf = 80)

  noise1 <- list(p = .4, q = .6, f = .5)  # substantial noise => 7 stddevs error
  CheckDecodeAveAndStds("Testing .DecodeBoolean (2/3)", CheckDecodeHelper, 100,
                        c(params_bool, noise1), map_bool, distribution_bool,
                        10^6,
                        tolerance_l1 = 7 * num_values,
                        tolerance_linf = 80)

  distribution_near_zero <- c(0.999, 0.001)
  names(distribution_near_zero) <- colnames(map_bool)

  CheckDecodeAveAndStds("Testing .DecodeBoolean (3/3)", CheckDecodeHelper, 100,
                        c(params_bool, noise2), map_bool,
                        distribution_near_zero, 10^6,
                        tolerance_l1 = 4 * num_values,
                        tolerance_linf = 80)
}

RunAll <- function() {
  TestEstimateBloomCounts()
  TestDecode()
  TestDecodeBool()
}

RunAll()
