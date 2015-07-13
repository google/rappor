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

source('tests/compare_dist.R')

TestProcessAll <- function() {
  ctx <- new.env()
  ctx$actual <- data.frame(string = c('v1', 'v2', 'v3'), proportion = c(0.2, 0.3, 0.5),
                           count = c(2, 3, 5))
  ctx$rappor <- data.frame(strings = c('v2', 'v3', 'v4'), proportion = c(0.1, 0.2, 0.3))

  metrics <- CompareRapporVsActual(ctx)$metrics
  str(metrics)

  # sum of rappor proportions
  checkEqualsNumeric(0.6, metrics$sum_proportion)

  # v1  v2  v3  v4
  # 0.2 0.3 0.5 0.0
  # 0.0 0.1 0.2 0.3

  # (0.2 + 0.2 + 0.3 + 0.3) / 2
  checkEqualsNumeric(0.5, metrics$total_variation)

  print(metrics$total_variation)
}

TestProcessAll()
