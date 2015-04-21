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

GenerateCounts <- function(params, true_map, partition, reports_per_client) {
  # Fast simulation of the marginal table for RAPPOR reports 
  # Args:
  #   params - parameters of the RAPPOR reporting process 
  #   true_map - hashed true inputs
  #   partition - allocation of clients between true values
  #   reports_per_client - number of reports (IRRs) per client
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

  # For each bit, the number of clients reporting this bit:
  clients_per_bit <- rep(apply(cohorts, 1, sum), each = params$k)
  
  # Computes the true number of bits set to one BEFORE PRR.
  true_ones <- apply(expanded * true_map$map, 1, sum)
    
  ones_in_prr <- 
    unlist(lapply(true_ones, 
                  function(x) rbinom(n = 1, size = x, prob = 1 - params$f / 2))) + 
    unlist(lapply(clients_per_bit - true_ones,  # clients where the bit is 0 
                  function(x) rbinom(n = 1, size = x, prob =  params$f / 2)))
  
  # Number of IRRs where each bit is reported (either as 0 or as 1)
  reports_per_bit <- clients_per_bit * reports_per_client
  
  ones_before_irr <- ones_in_prr * reports_per_client
  
  ones_after_irr <- 
    unlist(lapply(ones_before_irr, 
                  function(x) rbinom(n = 1, size = x, prob = params$q))) + 
    unlist(lapply(reports_per_bit - ones_before_irr,  
                  function(x) rbinom(n = 1, size = x, prob = params$p)))

  counts <- cbind(apply(cohorts, 1, sum) * reports_per_client,
        matrix(ones_after_irr, nrow = params$m, ncol = params$k, byrow = TRUE))

  if(any(is.na(counts)))
    stop("Failed to generate bit counts. Likely due to integer overflow.")
  
  counts
}

ComputePdf <- function(distr, range) {
  # Outputs discrete probability density function for a given distribution

  # These are the five distributions in gen_sim_input.py
  if (distr == 'exp') {
    pdf <- dexp(1:range, rate = 5 / range)
  } else if (distr == 'gauss') {
    half <- range / 2
    left <- -half + 1
    pdf <- dnorm(left : half, sd = range / 6)  
  } else if (distr == 'unif') {
    # e.g. for N = 4, weights are [0.25, 0.25, 0.25, 0.25]
    pdf <- dunif(1:range, max = range)
  } else if (distr == 'zipf1') {
    # Since the distrubition defined over a finite set, we allow the parameter
    # of the Zipf distribution to be 1.
    pdf <- sapply(1:range, function(x) 1 / x)
  } else if (distr == 'zipf1.5') {
    pdf <- sapply(1:range, function(x) 1 / x^1.5)
  }  
  else {
    stop(sprintf("Invalid distribution '%s'", distr))
  }

  pdf <- pdf / sum(pdf)  # normalize

  pdf
}

# Usage:
#
# $ ./gen_counts.R exp 10000 1 foo_params.csv foo_true_map.csv foo
#
# Inputs:
#   distribution name
#   number of clients
#   reports per client
#   parameters file
#   map file
#   prefix for output files
# Outputs:
#   foo_counts.csv 
#   foo_hist.csv
# 
# Warning: the number of reports in any cohort must be less than 
#          .Machine$integer.max

main <- function(argv) {
  distr <- argv[[1]]
  num_clients <- as.integer(argv[[2]])
  reports_per_client <- as.integer(argv[[3]])
  params_file <- argv[[4]]
  true_map_file <- argv[[5]]
  out_prefix <- argv[[6]]

  params <- ReadParameterFile(params_file)

  true_map <- ReadMapFile(true_map_file)

  num_unique_values <- length(true_map$strs)

  pdf <- ComputePdf(distr, num_unique_values)

  print("Distribution")
  print(pdf)

  # Computes the number of clients reporting each string 
  # according to the pre-specified distribution.
  partition <- RandomPartition(num_clients, pdf)
  print('PARTITION')
  print(partition)

  # Histogram
  true_hist <- data.frame(string = true_map$strs, count = partition)

  counts <- GenerateCounts(params, true_map, partition, reports_per_client)

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
