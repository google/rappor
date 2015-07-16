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
# $ ./gen_true_values.R exp 100 10000 1 foo.csv
#
# Inputs:
#   distribution name
#   size of the distribution's support
#   number of clients
#   reports per client
#   name of the output file
# Output:
#   csv file with reports sampled according to the specified distribution. 

GenerateTrueValues <- function(distr, distr_range, num_clients,
                            reports_per_client, num_cohorts) {

  # Sums to 1.0, e.g. [0.2 0.2 0.2 0.2 0.2] for uniform distribution of 5.
  pdf <- ComputePdf(distr, distr_range)

  num_reports <- num_clients * reports_per_client

  # Computes the number of clients reporting each value, where the numbers are
  # sampled according to pdf.  (sums to num_reports)
  partition <- RandomPartition(num_reports, pdf)
  
  value_ints <- rep(1:distr_range, partition)  # expand partition

  stopifnot(length(value_ints) == num_reports)

  # Shuffle values randomly (may take a few sec for > 10^8 inputs)
  value_ints <- sample(value_ints)

  # Reported values are strings, so prefix integers "v". Even slower than
  # shuffling.
  values <- sprintf("v%d", value_ints)

  # e.g. [1 1 2 2 3 3] if num_clients is 3 and reports_per_client is 2
  client_ints <- rep(1:num_clients, each = reports_per_client)

  # Cohorts are assigned to clients. Cohorts are 0-based.
  cohorts <- client_ints %% num_cohorts  # %% is integer modulus

  clients <- sprintf("c%d", client_ints)

  data.frame(client = clients, cohort = cohorts, value = values)
}

main <- function(argv) {
  distr <- argv[[1]]
  distr_range <- as.integer(argv[[2]])
  num_clients <- as.integer(argv[[3]])
  reports_per_client <- as.integer(argv[[4]])
  num_cohorts <- as.integer(argv[[5]])
  out_file <- argv[[6]]

  reports <- GenerateTrueValues(distr, distr_range, num_clients,
                                reports_per_client, num_cohorts)

  write.csv(reports, file = out_file, row.names = FALSE, quote = FALSE)
}

if (length(sys.frames()) == 0) {
  main(commandArgs(TRUE))
}
