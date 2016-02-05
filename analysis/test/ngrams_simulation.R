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

# Authors: vpihur@google.com (Vasyl Pihur) and fanti@google.com (Giulia Fanti)
#
# Tools used to simulate sending partial ngrams to the server for estimating the
#     dictionary of terms over which we want to learn a distribution. This
#     mostly contains functions that aid in the generation of synthetic data.

library(RUnit)
library(parallel)

source("analysis/R/encode.R")
source("analysis/R/decode.R")
source("analysis/R/simulation.R")
source("analysis/R/association.R")
source("analysis/R/decode_ngrams.R")

# The alphabet is the set of all possible characters that will appear in a
#     string. Here we use the English alphabet, but one might want to include
#     numbers or punctuation marks.
alphabet <- letters

GenerateCandidates <- function(alphabet, ngram_size = 2) {
  # Draws a random string for each individual in the
  #     population from distribution.
  #
  # Args:
  #   N: Number of individuals in the population
  #   num_strs: Number of strings from which to draw strings
  #   str_len: Length of each string
  #
  # Returns:
  #   Vector of strings for each individual in the population

  cands <- do.call(expand.grid, lapply(seq(ngram_size), function(i) alphabet))
  apply(cands, 1, function(x) paste0(x, collapse = ""))
}

GenerateString <- function(n) {
  # Generates a string of a given length from the alphabet.
  #
  # Args:
  #   n: Number of characters in the string
  #
  # Returns:
  #   String of length n
  paste0(sample(alphabet, n, replace = TRUE), collapse = "")
}

GeneratePopulation <- function(N, num_strs, str_len = 10,
                               distribution = 1) {
  # Generates a string for each individual in the population from distribution.
  #
  # Args:
  #   N: Number of individuals in the population
  #   num_strs: Number of strings from which to draw strings
  #   str_len: Length of each string
  #   distribution: which type of distribution to use
  #     1: Zipfian
  #     2: Geometric (exponential)
  #     3: Step function
  #
  # Returns:
  #   Vector of strings for each individual in the population

  strs <- sapply(1:num_strs, function(i) GenerateString(str_len))

  if (distribution == 1) {
    # Zipfian-ish distribution
    prob <- (1:num_strs)^20
    prob <- prob / sum(prob) + 0.001
    prob <- prob / sum(prob)
  } else if (distribution == 2) {
    # Geometric distribution (discrete approximation to exponential)
    p <- 0.3
    prob <- p * (1 - p)^(1:num_strs - 1)
    prob <- prob / sum(prob)
  } else {
    # Uniform
    prob <- rep(1 / num_strs, num_strs)
  }

  sample(strs, N, replace = TRUE, prob = prob)
}

SelectNGrams <- function(str, num_ngrams, size, max_str_len = 6) {
  # Selects which ngrams each user will encode and then submit.
  #
  # Args:
  #   str: String from which ngram is built.
  #   num_ngrams: Number of ngrams to choose
  #   size: Number of characters per ngram
  #   max_str_len: Maximum number of characters in the string
  #
  # Returns:
  #   List of each individual's ngrams and which positions the ngrams
  #       were drawn from.

  start <- sort(sample(seq(1, max_str_len, by = size), num_ngrams))
  ngrams <- mapply(function(x, y, str) substr(str, x, y),
                   start, start + size - 1,
                   MoreArgs = list(str = str))
  list(ngrams = ngrams, starts = start)
}

UpdateMapWithCandidates <- function(str_candidates, sim, params) {
  # Generates a new map based on the returned candidates.
  #     Normally this would be created on the spot by having the
  #     aggregator hash the string candidates. But since we already have
  #     the map from simulation, we'll just choose the appropriate
  #     column
  #
  # Arguments:
  #   str_candidates: Vector of string candidates
  #   sim: Simulation object containing the original map
  #   params: RAPPOR parameter list

  k <- params$k
  h <- params$h
  m <- params$m

  # First add the real candidates to the map
  valid_cands <- intersect(str_candidates, colnames(sim$full_map$map[[1]]))
  updated_map <- sim$full_map
  updated_map$map <- lapply(1:m, function(i)
                            sim$full_map$map[[i]][, valid_cands])

  # Now add the false positives (we can just draw random strings for
  #     these since they didn't appear in the original dataset anyway)
  new_cands <- setdiff(str_candidates, colnames(sim$full_map$map[[1]]))
  M <- length(new_cands)
  if (M > 0) {
    for (i in 1:m) {
      ones <- sample(1:k, M * h, replace = TRUE)
      cols <- rep(1:M, each = h)
      strs <- c(sort(valid_cands), new_cands)
      updated_map$map[[i]] <-
          do.call(cBind, list(updated_map$map[[i]],
                              sparseMatrix(ones, cols, dims = c(k, M))))
      colnames(updated_map$map[[i]]) <- strs
    }
  }
  if (class(updated_map$map[[1]]) == "logical") {
    updated_map$rmap <- unlist(updated_map$map)
    updated_map$rmap <- Matrix(updated_map$rmap, sparse = TRUE)
    colnames(updated_map$rmap) <- c(valid_cands, new_cands)
  } else {
    updated_map$rmap <- do.call("rBind", updated_map$map)
  }
  updated_map
}

SimulateNGrams <- function(N, ngram_params, str_len, num_strs = 10,
                           alphabet, params, distribution = 1) {
  # Simulates the creation and encoding of ngrams for each individual.
  #
  # Args:
  #   N: Number of individuals in the population
  #   ngram_params: Parameters about ngram size, etc.
  #   str_len: Length of each string
  #   num_strs: NUmber of strings in the dictionary
  #   alphabet: Alphabet used to generate strings
  #   params: RAPPOR parameters, like noise and cohorts
  #
  # Returns:
  #   List containing all the information needed for estimating and
  #       verifying the results.

  # Get the list of strings for each user
  strs <- GeneratePopulation(N, num_strs = num_strs,
                             str_len = str_len,
                             distribution)

  # Split them into ngrams and encode
  ngram <- lapply(strs, function(i)
                  SelectNGrams(i,
                               num_ngrams = ngram_params$num_ngrams_collected,
                               size = ngram_params$ngram_size,
                               max_str_len = str_len))

  cands <- GenerateCandidates(alphabet, ngram_params$ngram_size)
  map <- CreateMap(cands, params, FALSE)
  cohorts <- sample(1:params$m, N, replace = TRUE)

  g <- sapply(ngram, function(x) paste(x$starts, sep = "_",
                                       collapse = "_"))
  ug <- sort(unique(g))
  pairings <- t(sapply(ug, function(x)
                       sapply(strsplit(x, "_"), function(y) as.numeric(y))))

  inds <- lapply(1:length(ug), function(i) ind <- which(g == ug[i]))

  reports <- lapply(1:length(ug), function(k) {
    # Generate the ngram reports
    lapply(1:ngram_params$num_ngrams_collected, function(x) {
      EncodeAll(sapply(inds[[k]], function(j) ngram[[j]]$ngrams[x]),
                cohorts[inds[[k]]], map$map, params)})
  })
  cat("Encoded the ngrams.\n")
  # Now generate the full string reports
  full_map <- CreateMap(sort(unique(strs)), params, FALSE)
  full_reports <- EncodeAll(strs, cohorts, full_map$map, params)

  list(reports = reports, cohorts = cohorts, ngram = ngram, map = map,
       strs = strs, pairings = pairings, inds = inds, cands = cands,
       full_reports = full_reports, full_map = full_map)

}


EstimateDictionaryTrial <- function(N, str_len, num_strs,
                                    params, ngram_params,
                                    distribution = 3) {
  # Runs a single trial for simulation. Generates simulated reports,
  #     decodes them, and returns the result.
  #
  # Arguments:
  #   N: Number of users to simulation
  #   str_len: The length of strings to estimate
  #   num_strs: The number of strings in the dictionary
  #   params: RAPPOR parameter list
  #   ngram_params: Parameters related to the size of ngrams
  #   distribution: Tells what kind of distribution to use:
  #       1: Zipfian
  #       2: Geometric
  #       3: Uniform (default)
  #
  # Returns:
  #   List with recovered and true marginals.

  # We call the needed libraries here in order to make them available when this
  #     function gets called by BorgApply. Otherwise, they do not get included.
  library(glmnet)
  library(parallel)
  sim <- SimulateNGrams(N, ngram_params, str_len, num_strs = num_strs,
                        alphabet, params, distribution)

  res <- EstimateDictionary(sim, N, ngram_params, params)
  str_candidates <- res$found_candidates
  pairwise_candidates <- res$pairwise_candidates

  if (length(str_candidates) == 0) {
    return (NULL)
  }
  updated_map <- UpdateMapWithCandidates(str_candidates, sim, params)

  # Compute the marginal for this new set of strings
  variable_counts <- ComputeCounts(sim$full_reports, sim$cohorts, params)
  # Our dictionary estimate
  marginal <- Decode(variable_counts, updated_map$rmap, params)$fit
  # Estimate given full dictionary knowledge
  marginal_full <- Decode(variable_counts, sim$full_map$rmap, params)$fit
  # The true (sampled) data distribution
  truth <- sort(table(sim$strs)) / N

  list(marginal = marginal, marginal_full = marginal_full,
       truth = truth, pairwise_candidates = pairwise_candidates)
}
