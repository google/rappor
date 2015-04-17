#!/usr/bin/env Rscript
#
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
library(Matrix)  # for sparse matrices

source('tests/gen_counts.R')

TestGenerateCounts <- function() {
  report_params <- list(k = 4, m = 2)  # 2 cohorts, 4 bits each
  map <- Matrix(0, nrow = 8, ncol = 3, sparse = TRUE)  # 3 possible values
  map[1,] <- c(1, 0, 0)
  map[2,] <- c(0, 1, 0)
  map[3,] <- c(0, 0, 1)
  map[4,] <- c(1, 1, 1)  # 4th bit of the first cohort gets signal only from all
  map[5,] <- c(0, 0, 1)  # 1st bit of the second cohort gets signal from v3
    
  strs <- c('v1', 'v2', 'v3')
  
  maps <- list(map = map, strs = strs)
  
  partition <- c(3, 2, 1) * 10000
  v <- 100  # reports per client
  
  noise0 <- list(p = 0, q = 1, f = 0)  # no noise at all
  counts0 <- GenerateCounts(c(report_params, noise0), maps, partition, v)
  
  checkEqualsNumeric(sum(counts0[1,2:4]), counts0[1,1])
  checkEqualsNumeric(counts0[1,5], counts0[1,1])
  checkEqualsNumeric(partition[3] * v, counts0[1,4] + counts0[2,2])
  checkEqualsNumeric(sum(partition) * v, counts0[1,1] + counts0[2,1])
  
  pvalues <- chisq.test(counts0[,1] / v, p = c(.5, .5))$p.value
  for(i in 2:4)
    pvalues <- c(pvalues, 
                 chisq.test(
                   c(counts0[1,i] / v, partition[i - 1] - counts0[1,i] / v), 
                   p = c(.5, .5))$p.value)
  
  noise1 <- list(p = .5, q = .5, f = 0)  # truly random IRRs
  counts1 <- GenerateCounts(c(report_params, noise1), maps, partition, v)

  for(i in 2:4)
    for(j in 1:2)
      pvalues <- c(pvalues, 
                   chisq.test(c(counts1[j,1] - counts1[j,i], counts1[j,i]),
                                p = c(.5, .5))$p.value)

  noise2 <- list(p = 0, q = 1, f = 1.0)  # truly random PRRs
  counts2 <- GenerateCounts(c(report_params, noise2), maps, partition, v)
  
  checkEqualsNumeric(0, max(counts2 %% v))  # all entries must be divisible by v
  
  counts2 <- counts2 / v
  
  for(i in 2:4)
    for(j in 1:2)
      pvalues <- c(pvalues, 
                   chisq.test(c(counts2[j,1] - counts2[j,i], counts2[j,i]),
                              p = c(.5, .5))$p.value)
  
  checkTrue(min(pvalues) > 1E-9 && max(pvalues) < 1 - 1E-9, 
            "Chi-squared test failed")
}

TestRandomPartition <- function() {
  
  p1 <- RandomPartition(total = 100, dgeom(0:999, prob = .1))
  p2 <- RandomPartition(total = 1000, dnorm(1:1000, mean = 500, sd = 1000 / 6))
  p3 <- RandomPartition(total = 10000, dunif(1:1000))
  
  # Totals must check out.
  checkEqualsNumeric(100, sum(p1))
  checkEqualsNumeric(1000, sum(p2))
  checkEqualsNumeric(10000, sum(p3))  
  
  # Initialize the weights vector to 1 0 1 0 1 0 ...
  weights <- rep(c(1, 0), 100)
  
  p4 <- RandomPartition(total = 10000, weights)
  
  # Check that all mass is allocated to non-zero weights.
  checkEqualsNumeric(10000, sum(p4[weights == 1]))
  checkTrue(all(p4[weights == 0] == 0))

  p5 <- RandomPartition(total = 1000000, c(1, 2, 3, 4))
  p.value <- chisq.test(p5, p = c(.1, .2, .3, .4))$p.value
  
  # Apply the chi squared test and fail if p.value is too high or too low.
  # Probability of failure is 2 * 1E-9, which should never happen.
  checkTrue((p.value > 1E-9) && (p.value <  1 - 1E-9))
}

TestAll <- function(){
  TestRandomPartition()  
  TestGenerateCounts()
}

TestAll()