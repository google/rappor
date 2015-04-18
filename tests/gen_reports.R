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

source('tests/gen_counts.R')

# Usage:
#
# $ ./gen_reports.R exp 100 10000 1 foo.csv
#
# Inputs:
#   distribution name
#   size of the distribution's support
#   number of clients
#   reports per client
#   name of the output file
# Output:
#   csv file with reports sampled according to the specified distribution. 

main <- function(argv) {
  distr <- argv[[1]]
  distr_range <- as.integer(argv[[2]])
  num_clients <- as.integer(argv[[3]])
  reports_per_client <- as.integer(argv[[4]])
  out_file <- argv[[5]]

  pdf <- ComputePdf(distr, distr_range)

  print("Distribution")
  print(pdf)

  # Computes the number of clients reporting each value, where the numbers are
  # sampled according to pdf.
  partition <- RandomPartition(num_clients, pdf)
  
  print('PARTITION')
  print(partition)

  values <- rep(1:distr_range, partition)  # expand partition
  
  stopifnot(length(values) == num_clients)

  # Shuffle values randomly (may take a few sec for > 10^8 inputs)
  values <- sample(values)

  # Obtain reports by prefixing values with "v"s. Even slower than shuffling.
  reports <- sprintf("v%d", values)

  reports <- cbind(1:num_clients, reports)  # paste together "1 v342"
  reports <- reports[rep(1:nrow(reports), each = reports_per_client), ]

  write.table(reports, file = out_file, row.names = FALSE, col.names = FALSE, 
              sep = ",", quote = FALSE)
}

if (length(sys.frames()) == 0) {
  main(commandArgs(TRUE))
}
