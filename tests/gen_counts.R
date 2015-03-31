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

RandomPartition <- function(total, weights){
  # Outputs a random partition according to a specified distribution
  # Args:
  #   total - number of balls
  #   weights - vector encoding the probability that a ball lands into a bin
  # Returns:
  #   an integer vector summing up to total
  # Example:
  #   > RandomPartition(100, c(3, 2, 1, 0, 1))
  #   [1] 47 24 15  0 14
  bins <- length(weights)

  if (total == 0) {
    result = rep(0, bins)
  } else {
    if (any(weights < 0))
      stop("Weights cannot be negative")
    
    if (sum(weights) == 0)
      stop("Weights cannot sum up to 0")
      
    # idiomatic way:
    #   rnd_list = sample(strs, total, replace = TRUE, weights)
    #   apply(as.array(strs), 1, function(x) length(rnd_list[rnd_list == x]))
    #
    # The following is much faster for larger totals. We can replace a loop with
    # (tail) recusion, but R chokes with the recursion depth > 850.
    
    result <- vector(length = bins)
    w <- sum(weights)

    for (i in 1:bins) {
      # invariant: w = sum(weights[i:bins]) 
      # rather than computing sum every time leading to quadratic time, keep 
      # updating it
      if (w > 0) {
        p <- weights[i] / w
        # draw the number of balls falling into the current bin
        rnd_draw <- rbinom(n = 1, size = total, prob = p)
        result[i] <- rnd_draw  # push rnd_draw balls from total to result[i]
        total <- total - rnd_draw
        w <- w - weights[i]  
      }
    }
  }
  
  result
}

GenerateCounts <- function(params, total, true_map, weights = NULL){
  # Fast simulation of the marginal table for RAPPOR reports 
  # Args:
  #   params - parameters of the RAPPOR reporting process 
  if (nrow(true_map$map) != (params$m * params$k)) {
    stop(cat("Map does not match the params file!",
                 "mk =", params$m * params$k,
                 "nrow(map):", nrow(true_map$map),
                 sep = " "))
  }
  
  if(is.null(weights))
    weights <- rep(1, length(true_map$strs))  # uniform by default
  
  if (length(true_map$strs) != length(weights)) {
    stop(cat("Dimensions of weights do not match:",
              "m =", length(true_map$strs), "weights col:", length(weights),
              sep = " "))
  }
  
  # Computes the number of clients reporting each string 
  # according to the pre-specified distribution.
  actual <- RandomPartition(total, weights)
  
  # For each reporting type computes its allocation to cohorts.  
  # Output is an m x strs matrix.
  cohorts <- as.matrix(
                apply(as.data.frame(actual), 1, 
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
  # probability that a true 0 is reported as "0"
  qstar <- (1 - f / 2) * (1 - p) + (f / 2) * (1 - q)
  
  reported_ones <- 
    unlist(lapply(counts_ones, 
                  function(x) rbinom(n = 1, size = x, prob = pstar))) + 
    unlist(lapply(counts_zeros, 
                  function(x) rbinom(n = 1, size = x, prob = qstar)))
  
  cbind(apply(cohorts, 1, sum),
        matrix(reported_ones, nrow = params$m, ncol = params$k, byrow = TRUE))
}
