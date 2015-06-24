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
# $ ./gen_assoc_reports.R 100 20 10000 foo.csv
#
# Inputs:
#   size of the distribution's support for var 1
#   size of the distribution's support for var 2
#   number of clients
#   name of the output file
# Output:
#   csv file with reports sampled according to the specified distribution. 

main <- function(argv) {
  n <- list(as.integer(argv[[1]]), as.integer(argv[[2]]))
  N <- as.integer(argv[[3]])
  out_file <- argv[[4]]

  # Sample values to compute partition
  # Resulting distribution is a correlated zipf x zipf
  # distribution over 2 variables
  PartitionWithCorrelation <- function(size, support, index) {
    part <- RandomPartition(size, ComputePdf("zipf1.5", support))
    if (index %% 2 == 0) {part} else {rev(part)}
  }
  
  # Zipfian over n[[1]] strings
  part <- RandomPartition(N, ComputePdf("zipf1.5", n[[1]]))
  # Zipfian over n[[2]] strings for each of variable 1
  final_part <- as.vector(sapply(1:n[[1]],
                  function(i) PartitionWithCorrelation(part[[i]], n[[2]], i)))
  
  final_part <- matrix(final_part, nrow = n[[1]], byrow = TRUE)
  rownames(final_part) <- sapply(1:n[[1]], function(x) paste("str", x, sep = ""))
  colnames(final_part) <- sapply(1:n[[2]], function(x) paste("opt", x, sep = ""))
  distr <- final_part/sum(final_part)
  print("DISTRIBUTION")
  print(distr)

  print('PARTITION')
  print(final_part)

  # Expand partition
  values <- list(
    rep(1:n[[1]], rowSums(final_part)),
    unlist(sapply(1:n[[1]], function(x) rep(1:n[[2]], final_part[x, ]))))
  
  stopifnot((length(values[[1]]) == N) &
              (length(values[[2]]) == N))

  # Shuffle values randomly (may take a few sec for > 10^8 inputs)
  perm <- sample(N)
  values <- list(values[[1]][perm], values[[2]][perm])

  # Obtain reports by prefixing values with "v"s. Even slower than shuffling.
  reports <- list(sprintf("str%d", values[[1]]),
                  sprintf("opt%d", values[[2]]))

  reports <- cbind(1:N, reports[[1]], reports[[2]])  # paste together "1 v342"

  write.table(reports, file = out_file, row.names = FALSE, col.names = FALSE, 
              sep = ",", quote = FALSE)
}

if (length(sys.frames()) == 0) {
  main(commandArgs(TRUE))
}
