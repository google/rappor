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

# Authors: vpihur@google.com (Vasyl Pihur), fanti@google.com (Giulia Fanti)

library(RUnit)
source("analysis/R/encode.R")
source("analysis/R/decode.R")
source("analysis/R/simulation.R")
source("analysis/R/association.R")

SamplePopulations <- function(N, num_variables = 1, params,
                              variable_opts) {
  # Samples a number of variables. User specifies the number of variables
  #     and some desired properties of those variables.
  #
  # Args:
  #   N: Number of reports to generate.
  #   params: RAPPOR parameters, like Bloom filter size, number of
  #       hash bits, etc.
  #   variable_opts: List of options for generating the ground truth:
  #       independent = whether distinct variables should be independently drawn
  #       deterministic = whether the variables should be drawn from a
  #           Poisson distribution or uniformly assigned across the range
  #           of 1:num_strings
  #       num_strings: Only does something if deterministic == TRUE, and
  #           specifies how many strings to use in the uniform assignment
  #           of ground truth strings.
  #
  # Returns:
  #   RAPPOR simulated ground truth for each piece of data.

  m <- params$m
  num_strings <- variable_opts$num_strings

  if (variable_opts$deterministic) {
    # If a deterministic assignment is desired, evenly distribute
    #     strings across all cohorts.

    reps <- ceiling(N / num_strings)
    variables <- lapply(1:num_variables,
                        function(i)
                        as.vector(sapply(1:num_strings, function(x)
                                         rep(x, reps)))[1:N])
    cohorts <- lapply(1:num_variables,
                      function(i) rep(1:m, ceiling(N / m))[1:N])
  } else {
    # Otherwise, draw from a Poisson random variable
    variables <- lapply(1:num_variables, function(i) rpois(N, 1) + 1)

    # Randomly assign cohorts in each dimension
    cohorts <- lapply(1:num_variables,
                      function(i) sample(1:params$m, N, replace = TRUE))

    if (!variable_opts$independent) {
      # If user wants dependent RVs, subsequent variables are closely correlated
      # with the first variable in the foll. manner:
      #   variable_i ~ variable_1 + (i-1) Bernoulli(0.5)

      bernoulli_corr <- function(x) {
        variables[[1]] + (x - 1) * sample(c(0, 1), N, replace = TRUE)}

      variables[2:num_variables] <- lapply(2:num_variables,
                                           function(x) bernoulli_corr(x))
    }
  }
  list(variables = variables, cohorts = cohorts)
}

Simulate <- function(N, num_variables, params, variable_opts = NULL,
                     truth = NULL, basic = FALSE) {
  if (is.null(truth)) {
    truth <- SamplePopulations(N, num_variables, params,
                               variable_opts)
  }
  strs <- lapply(truth$variables, function(x) sort(seq(max(x))))
  # strs <- lapply(truth$variables, function(x) sort(unique(x)))
  # strs <- lapply(truth$variables, function(x) 1:length(unique(x)))

  # Construct lists of maps and reports
  if (variable_opts$deterministic) {
    # Build the maps
    map <- CreateMap(strs[[1]], params, FALSE, basic = basic)
    maps <- lapply(1:num_variables, function(x) map)
    # Build the reports
    report <- EncodeAll(truth$variables[[1]], truth$cohorts[[1]],
                        map$map, params)
    reports <- lapply(1:num_variables, function(x) report)
  } else {
    # Build the maps
    maps <- lapply(1:num_variables, function(x)
                   CreateMap(strs[[x]], params, FALSE,
                             basic = basic))
    # Build the reports
    reports <- lapply(1:num_variables, function(x)
                      EncodeAll(truth$variables[[x]], truth$cohorts[[x]],
                                maps[[x]]$map, params))
  }

  list(reports = reports, cohorts = truth$cohorts,
       truth = truth$variables, maps = maps, strs = strs)

}

# ----------------Actual testing starts here--------------- #
TestComputeDistributionEM <- function() {
  # Test various aspects of ComputeDistributionEM in association.R.
  #     Tests include:
  #     Test 1: Compute a joint distribution of uniformly distributed,
  #         perfectly correlated strings
  #     Test 2: Compute a marginal distribution of uniformly distributed strings
  #     Test 3: Check the "other" category estimation works by removing
  #          a string from the known map.
  #     Test 4: Test that the variance from EM algorithm is 1/N when there
  #          is no noise in the system.
  #     Test 5: Check that the right answer is still obtained when f = 0.2.

  num_variables <- 3
  N <- 100

  # Initialize the parameters
  params <- list(k = 12, h = 2, m = 4, p = 0, q = 1, f = 0)
  variable_opts <- list(deterministic = TRUE, num_strings = 2,
                        independent = FALSE)
  sim <- Simulate(N, num_variables, params, variable_opts)

  # Test 1: Delta function pmf
  joint_dist <- ComputeDistributionEM(sim$reports,
                                      sim$cohorts, sim$maps,
                                      ignore_other = TRUE, params,
                                      marginals = NULL,
                                      estimate_var = FALSE)
  # The recovered distribution should be close to the delta function.
  checkTrue(abs(joint_dist$fit["1", "1", "1"] - 0.5) < 0.01)
  checkTrue(abs(joint_dist$fit["2", "2", "2"] - 0.5) < 0.01)

  # Test 2: Now compute a marginal using EM
  dist <- ComputeDistributionEM(list(sim$reports[[1]]),
                                list(sim$cohorts[[1]]),
                                list(sim$maps[[1]]),
                                ignore_other = TRUE,
                                params, marginals = NULL,
                                estimate_var = FALSE)
  checkTrue(abs(dist$fit["1"] - 0.5) < 0.01)

  # Test 3: Check that the "other" category is correctly computed
  # Build a modified map with no column 2 (i.e. we only know that string
  #     "1" is a valid string
  map <- sim$maps[[1]]
  small_map <- map

  for (i in 1:params$m) {
    locs <- which(map$map[[i]][, 1])
    small_map$map[[i]] <- sparseMatrix(locs, rep(1, length(locs)),
                                       dims = c(params$k, 1))
    locs <- which(map$rmap[, 1])
    colnames(small_map$map[[i]]) <- sim$strs[1]
  }
  small_map$rmap <- do.call("rBind", small_map$map)

  dist <- ComputeDistributionEM(list(sim$reports[[1]]),
                                list(sim$cohorts[[1]]),
                                list(small_map),
                                ignore_other = FALSE,
                                params,
                                marginals = NULL,
                                estimate_var = FALSE)

  # The recovered distribution should be uniform over 2 strings.
  checkTrue(abs(dist$fit[1] - 0.5) < 0.1)


  # Test 4: Test the variance is 1/N
  variable_opts <- list(deterministic = TRUE, num_strings = 1)
  sim <- Simulate(N, num_variables = 1, params, variable_opts)
  dist <- ComputeDistributionEM(sim$reports, sim$cohorts,
                                sim$maps, ignore_other = TRUE,
                                params, marginals = NULL,
                                estimate_var = TRUE)

  checkEqualsNumeric(dist$em$var_cov[1, 1], 1 / N)

  # Test 5: Check that when f=0.2, we still get a good estimate
  params <- list(k = 12, h = 2, m = 2, p = 0, q = 1, f = 0.2)
  variable_opts <- list(deterministic = TRUE, num_strings = 2)
  sim <- Simulate(N, num_variables = 2, params, variable_opts)
  dist <- ComputeDistributionEM(sim$reports, sim$cohorts,
                                sim$maps, ignore_other = TRUE,
                                params, marginals = NULL,
                                estimate_var = FALSE)

  checkTrue(abs(dist$fit["1", "1"] - 0.5) < 0.15)
  checkTrue(abs(dist$fit["2", "2"] - 0.5) < 0.15)

  # Test 6: Check the computed joint distribution with randomized
  # correlated inputs from the Poisson distribution
  # Expect to have correlation between strings n and n + 1
  N <- 1000
  params <- list(k = 16, h = 2, m = 4, p = 0.1, q = 0.9, f = 0.1)
  variable_opts <- list(deterministic = FALSE, independent = FALSE)
  sim <- Simulate(N, num_variables = 2, params, variable_opts)
  dist <- ComputeDistributionEM(sim$reports, sim$cohorts,
                                sim$maps, ignore_other = TRUE,
                                params, marginals = NULL,
                                estimate_var = FALSE)

  print_dist <- TRUE  # to print joint distribution, set to TRUE

  if (print_dist) {
    # dist$fit[dist$fit<1e-4] <- 0
    # Sort by row names and column names to visually see correlation
    print(dist$fit[sort(rownames(dist$fit)), sort(colnames(dist$fit))])
  }

  # Check for correlations (constants chosen heuristically to get good
  # test confidence with small # of samples)
  # Should have mass roughly 1/2e and 1/2e each
  checkTrue(abs(dist$fit["1", "1"] - dist$fit["1", "2"]) < 0.1)
  checkTrue(abs(dist$fit["2", "2"] - dist$fit["2", "3"]) < 0.1)

  # Should have mass roughly 1/4e and 1/4e each
  checkTrue(abs(dist$fit["3", "3"] - dist$fit["3", "4"]) < 0.06)

  # Check for lack of probability mass
  checkTrue(dist$fit["1", "3"] < 0.02)
  checkTrue(dist$fit["1", "4"] < 0.02)
  checkTrue(dist$fit["2", "1"] < 0.02)
  checkTrue(dist$fit["2", "4"] < 0.02)
  checkTrue(dist$fit["3", "1"] < 0.02)
  checkTrue(dist$fit["3", "2"] < 0.02)
}