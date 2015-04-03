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

source('tests/gen_counts.R')

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

TestRandomPartition()
