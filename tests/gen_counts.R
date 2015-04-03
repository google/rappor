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

source('analysis/R/read_input.R')

RandomPartition <- function(total, weights) {
  # Outputs a random partition according to a specified distribution
  # Args:
  #   total - number of balls
  #   weights - vector encoding the probability that a ball lands into a bin
  # Returns:
  #   an integer vector summing up to total
  # Example:
  #   > RandomPartition(100, c(3, 2, 1, 0, 1))
  #   [1] 47 24 15  0 14
  if (any(weights < 0))
    stop("Weights cannot be negative")
  
  if (sum(weights) == 0)
    stop("Weights cannot sum up to 0")
  
  bins <- length(weights)
  result <- rep(0, bins)
  
  # idiomatic way:
  #   rnd_list <- sample(strs, total, replace = TRUE, weights)
  #   apply(as.array(strs), 1, function(x) length(rnd_list[rnd_list == x]))
  #
  # The following is much faster for larger totals. We can replace a loop with
  # (tail) recusion, but R chokes with the recursion depth > 850.
  
  w <- sum(weights)

  for (i in 1:bins) 
    if (total > 0) {  # if total == 0, nothing else to do  
      # invariant: w = sum(weights[i:bins]) 
      # rather than computing sum every time leading to quadratic time, keep 
      # updating it
  
      # The probability p is clamped to [0, 1] to avoid under/overflow errors.
      p <- min(max(weights[i] / w, 0), 1) 
      # draw the number of balls falling into the current bin
      rnd_draw <- rbinom(n = 1, size = total, prob = p)
      result[i] <- rnd_draw  # push rnd_draw balls from total to result[i]
      total <- total - rnd_draw
      w <- w - weights[i]  
  }

  return(result)
}

GenerateCounts <- function(params, true_map, partition) {
  # Fast simulation of the marginal table for RAPPOR reports 
  # Args:
  #   params - parameters of the RAPPOR reporting process 
  #   total - number of reports
  #   true_map - hashed true inputs
  #   weights - vector encoding the probability that a ball lands into a bin
  if (nrow(true_map$map) != (params$m * params$k)) {
    stop(cat("Map does not match the params file!",
                 "mk =", params$m * params$k,
                 "nrow(map):", nrow(true_map$map),
                 sep = " "))
  }
  
  # For each reporting type computes its allocation to cohorts.  
  # Output is an m x strs matrix.
  cohorts <- as.matrix(
                apply(as.data.frame(partition), 1, 
                      function(count) RandomPartition(count, rep(1, params$m))))
  
  # Expands to (m x k) x strs matrix, where each element (corresponding to the 
  # bit in the aggregate Bloom filter) is repeated k times. 
  expanded <- apply(cohorts, 2, function(vec) rep(vec, each = params$k))
  
  # Computes the number of bits set to one BEFORE privacy-preserving transform.
  counts_ones <- apply(expanded * true_map$map, 1, sum)
  
  # Computes the number of bits set to zero BEFORE privacy-preserving transform.
  counts_zeros <- rep(apply(cohorts, 1, sum), each = params$k) - counts_ones
  
  p <- params$p
  q <- params$q
  f <- params$f

  # probability that a true 1 is reported as "1"
  pstar <- (1 - f / 2) * q + (f / 2) * p
  # probability that a true 0 is reported as "1"
  qstar <- (1 - f / 2) * p + (f / 2) * q
  
  reported_ones <- 
    unlist(lapply(counts_ones, 
                  function(x) rbinom(n = 1, size = x, prob = pstar))) + 
    unlist(lapply(counts_zeros, 
                  function(x) rbinom(n = 1, size = x, prob = qstar)))
  
  counts <- cbind(apply(cohorts, 1, sum),
        matrix(reported_ones, nrow = params$m, ncol = params$k, byrow = TRUE))

  counts
}

# Usage:
#
# $ ./gen_counts.R foo_params.csv foo_true_map.csv exp 10000 \
#                  foo_counts.csv
#
# 4 inputs and 1 output.

main <- function(argv) {
  params_file <- argv[[1]]
  true_map_file <- argv[[2]]
  dist <- argv[[3]]
  num_reports <- as.integer(argv[[4]])
  out_prefix <- argv[[5]]

  params <- ReadParameterFile(params_file)

  true_map <- ReadMapFile(true_map_file)
  # print(true_map$strs)

  num_unique_values <- length(true_map$strs)

  # These are the three distributions in gen_sim_input.py
  if (dist == 'exp') {
    # NOTE: gen_sim_input.py hard-codes lambda = N/5 for 'exp'
    weights <- dexp(1:num_unique_values, rate = 5 / num_unique_values)
  } else if (dist == 'gauss') {
    # NOTE: gen_sim_input.py hard-codes stddev = N/6 for 'exp'
    half <- num_unique_values / 2
    left <- -half + 1
    weights <- dnorm(left : half, sd = num_unique_values / 6)  
  } else if (dist == 'unif') {
    # e.g. for N = 4, weights are [0.25, 0.25, 0.25, 0.25]
    weights <- dunif(1:num_unique_values, max = num_unique_values)
  } else {
    stop(sprintf("Invalid distribution '%s'", dist))
  }
  print("weights")
  print(weights)

  if (length(true_map$strs) != length(weights)) {
    stop(cat("Dimensions of weights do not match:",
              "m =", length(true_map$strs), "weights col:", length(weights),
              sep = " "))
  }

  # Computes the number of clients reporting each string 
  # according to the pre-specified distribution.
  partition <- RandomPartition(num_reports, weights)
  print('PARTITION')
  print(partition)

  # Histogram
  true_hist <- data.frame(string = true_map$strs, count = partition)

  counts <- GenerateCounts(params, true_map, partition)

  # Now create a CSV file

  # Opposite of ReadCountsFile in read_input.R
  # http://stackoverflow.com/questions/6750546/export-csv-without-col-names
  counts_path <- paste0(out_prefix, '_counts.csv')
  write.table(counts, file = counts_path,
              row.names = FALSE, col.names = FALSE, sep = ',')
  cat(sprintf('Wrote %s\n', counts_path))

  # TODO: Don't write strings that appear 0 times?

  hist_path <- paste0(out_prefix, '_hist.csv')
  write.csv(true_hist, file = hist_path, row.names = FALSE)
  cat(sprintf('Wrote %s\n', hist_path))
}

if (length(sys.frames()) == 0) {
  main(commandArgs(TRUE))
}
