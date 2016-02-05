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

# Author: fanti@google.com (Giulia Fanti)
#
# Tests the unknown unknowns dictionary estimation functions.
#     There are two main components involved in estimating this unknown
#     distribution:
#          a) Find the pairwise ngrams that co-occur often.
#          b) Determine which full strings are consisted with all pairwise
#             relations.
#
#     TestEstimateDictionary() tests the full pipeline, including parts (a)
#         and (b).
#     TestFindFeasibleStrings() tests only part (b).
#     Both tests generate their own data.

library(parallel)
source("analysis/R/encode.R")
source("analysis/R/decode.R")
source("analysis/R/simulation.R")
source("analysis/R/association.R")
source("analysis/R/decode_ngrams.R")
source("analysis/test/ngrams_simulation.R")
alphabet <- letters
options(warn = -1)

GeneratePopulation <- function(N, num_strs, str_len = 10,
                               distribution = NULL) {
  # Generates a /deterministic/ string for each individual in the
  #     population from distribution.
  #
  # Args:
  #   N: Number of individuals in the population
  #   num_strs: Number of strings from which to draw strings
  #   str_len: Length of each string
  #   distribution: Just here for compatibility with original
  #       GeneratePopulation function in ngrams_simulation.R
  #
  # Returns:
  #   Vector of strings for each individual in the population

  strs <- sapply(1:num_strs, function(i) {
    paste0(alphabet[(str_len * (i - 1) + 1):(str_len * i)], collapse = "")
  })

  # Uniform distribution
  prob <- rep(1 / num_strs, num_strs)
  sample(strs, N, replace = TRUE, prob = prob)
}

TestEstimateDictionary <- function() {
  # Tests that the algorithm without noise recovers a uniform
  #     string population correctly.

  # Compute the strings from measuring only 2 ngrams
  N <- 100
  str_len <- 6
  ngram_size <- 2
  num_ngrams <- str_len / ngram_size
  num_strs <- 1

  params <- list(k = 128, h = 4, m = 2, p = 0, q = 1, f = 0)

  ngram_params <- list(ngram_size = ngram_size, num_ngrams = num_ngrams,
                       num_ngrams_collected = 2)

  sim <- SimulateNGrams(N, ngram_params, str_len, num_strs = num_strs,
                        alphabet, params, distribution = 3)

  res <- EstimateDictionary(sim, N, ngram_params, params)

  # Check that the correct strings are found
  if (num_strs == 1) {
    checkTrue(res$found_candidates == sort(unique(sim$strs)))
  } else {
    checkTrue (all.equal(res$found_candidates, sort(unique(sim$strs))))
  }
}

TestFindFeasibleStrings <- function() {
  # Tests that FindPairwiseCandidates weeds out false positives.
  #     We test this by adding false positives to the pairwise estimates.
  N <- 100
  str_len <- 6
  ngram_size <- 2
  num_ngrams <- str_len / ngram_size
  num_strs <- 2

  params <- list(k = 128, h = 4, m = 2, p = 0, q = 1, f = 0)

  ngram_params <- list(ngram_size = ngram_size, num_ngrams = num_ngrams,
                       num_ngrams_collected = 2)

  sim <- SimulateNGrams(N, ngram_params, str_len, num_strs = num_strs,
                        alphabet, params)

  pairwise_candidates <- FindPairwiseCandidates(sim, N, ngram_params,
                                                params)$candidate_strs
  cat("Found the pairwise candidates. \n")

  pairwise_candidates[[1]] <- rbind(pairwise_candidates[[1]], c("ab", "le"))

  if (is.null(pairwise_candidates)) {
    return (FALSE)
  }

  conn <- file('graph.txt', 'w+')
  WriteKPartiteGraph(conn,
                     pairwise_candidates,
                     sim$pairings,
                     ngram_params$num_ngrams,
                     ngram_params$ngram_size)

  close(conn)
  cat("Wrote graph.txt\n")

  found_candidates <- FindFeasibleStrings(pairwise_candidates,
                                          sim$pairings,
                                          ngram_params$num_ngrams,
                                          ngram_params$ngram_size)
  # Check that the correct strings are found
  if (num_strs == 1) {
    checkTrue(found_candidates == sort(unique(sim$strs)))
  } else {
    checkTrue(all.equal(found_candidates, sort(unique(sim$strs))))
  }
}
