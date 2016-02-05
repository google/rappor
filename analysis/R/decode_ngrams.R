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

#
# This file has functions that aid in the estimation of a distribution when the
#     dictionary is unknown. There are functions for estimating pairwise joint
#     ngram distributions, pruning out false positives, and combining the two
#     steps.

FindPairwiseCandidates <- function(report_data, N, ngram_params, params) {
  # Finds the pairwise most likely ngrams.
  #
  # Args:
  #   report_data: Object containing data relevant to reports:
  #       $inds: The indices of reports collected using various pairs
  #       $cohorts: The cohort of each report
  #       $map: The map used for all the ngrams
  #       $reports: The reports used for each ngram and full string
  #   N: Number of reports collected
  #   ngram_params: Parameters related to ngram size
  #   params: Parameter list.
  #
  # Returns:
  #   List: list of matrices, list of pairwise distributions.

  inds <- report_data$inds
  cohorts <- report_data$cohorts
  num_ngrams_collected <- ngram_params$num_ngrams_collected
  map <- report_data$map
  reports <- report_data$reports

  # Cycle over all the unique pairs of ngrams being collected
  found_candidates <- list()

  # Generate the map list to be used for all ngrams
  maps <- lapply(1:num_ngrams_collected, function(x) map)
  num_candidate_ngrams <- length(inds)

  .ComputeDist <- function(i, inds, cohorts, reports, maps, params,
                           num_ngrams_collected) {
    library(glmnet)
    ind <- inds[[i]]
    cohort_subset <- lapply(1:num_ngrams_collected, function(x)
                            cohorts[ind])
    report_subset <- reports[[i]]
    new_dist <- ComputeDistributionEM(report_subset,
                                      cohort_subset,
                                      maps, ignore_other = FALSE,
                                      params = params, estimate_var = FALSE)
    new_dist
  }

  # Compute the pairwise distributions (could be parallelized)
  dists <- lapply(seq(num_candidate_ngrams), function(i)
                  .ComputeDist(i, inds, cohorts, reports, maps,
                               params, num_ngrams_collected))

  dists_null <- sapply(dists, function(x) is.null(x))
  if (any(dists_null)) {
    return (list(found_candidates = list(), dists = dists))
  }
  cat("Found the pairwise ngram distributions.\n")

  # Find the threshold for choosing "significant" ngram pairs
  f <- params$f; q <- params$q; p <- params$p
  q2 <- .5 * f * (p + q) + (1 - f) * q
  p2 <- .5 * f * (p + q) + (1 - f) * p
  std_dev_counts <- sqrt(p2 * (1 - p2) * N) / (q2 - p2)
  (threshold <- std_dev_counts / N)
  threshold <- 0.04

  # Filter joints to remove infrequently co-occurring ngrams.
  candidate_strs <- lapply(1:num_candidate_ngrams, function(i) {
    fit <- dists[[i]]$fit
    edges <- which(fit > threshold, arr.ind = TRUE, FALSE)

    # Recover the list of strings that seem significant
    found_candidates <- sapply(1:ncol(edges), function(x) {
      chunks <- sapply(edges[, x],
                       function(j) dimnames(fit)[[x]][j])
      chunks
    })
    # sapply returns either "character" vector (for n=1) or a matrix.  Convert
    # it to a matrix.  This can be seen as follows:
    #
    # > class(sapply(1:5, function(x) "a"))
    # [1] "character"
    # > class(sapply(1:5, function(x) c("a", "b")))
    # [1] "matrix"
    found_candidates <- rbind(found_candidates)

    # Remove the "others"
    others <- which(found_candidates == "Other")
    if (length(others) > 0) {
      other <- which(found_candidates == "Other", arr.ind = TRUE)[, 1]
      # drop = FALSE necessary to keep it a matrix
      found_candidates <- found_candidates[-other, , drop = FALSE]
    }

    found_candidates
  })
  if (any(lapply(found_candidates, function(x) length(x)) == 0)) {
    return (NULL)
  }

  list(candidate_strs = candidate_strs, dists = dists)
}

FindFeasibleStrings <- function(found_candidates, pairings, num_ngrams,
                                ngram_size) {
  # Uses the list of strings found by the pairwise comparisons to build
  #     a list of full feasible strings. This relies on the iterative,
  #     graph-based approach.
  #
  # Args:
  #   found_candidates: list of candidates found by each pairwise decoding
  #   pairings: Matrix of size 2x(num_ngrams choose 2) listing all the
  #       ngram position pairings.
  #   num_ngrams: The total number of ngrams per word.
  #   ngram_size: Number of characters per ngram
  #
  # Returns:
  #   List of full string candidates.

  # Which ngram pairs are adjacent, i.e. of the form (i,i+1)
  adjacent <- sapply(seq(num_ngrams - 1), function(x) {
    c(1 + (x - 1) * ngram_size, x * ngram_size + 1)
  })

  adjacent_pairs <- apply(adjacent, 2, function(x) {
    which(apply(pairings, 1, function(y) identical(y, x)))
  })

  # The first set of candidates are ngrams found in positions 1 and 2
  active_cands <- found_candidates[[adjacent_pairs[1]]]
  if (class(active_cands) == "list") {
    return (list())
  } else {
    active_cands <- as.data.frame(active_cands)
  }

  # Now check successive ngrams to find consistent combinations
  #     i.e. after ngrams 1-2, check 2-3, 3-4, 4-5, etc.
  for (i in 2:length(adjacent_pairs)) {
    if (nrow(active_cands) == 0) {
      return (list())
    }
    new_cands <- found_candidates[[adjacent_pairs[i]]]
    new_cands <- as.data.frame(new_cands)
    # Builds the set of possible candidates based only on ascending
    #     candidate pairs
    active_cands <- BuildCandidates(active_cands, new_cands)
  }

  if (nrow(active_cands) == 0) {
    return (list())
  }
  # Now refine these candidates using non-adjacent bigrams
  remaining <- (1:(num_ngrams * (num_ngrams - 1) / 2))[-c(1, adjacent_pairs)]
  # For each non-adjacent pair, make sure that all the candidates are
  #     consistent (in this phase, candidates can ONLY be eliminated)

  for (i in remaining) {
    new_cands <- found_candidates[[i]]
    new_cands <- as.data.frame(new_cands)
    # Prune out all candidates that do not agree with new_cands
    active_cands <- PruneCandidates(active_cands, pairings[i, ],
                                    ngram_size,
                                    new_cands = new_cands)
  }
  # Consolidate the string ngrams into a full string representation
  if (length(active_cands) > 0) {
    active_cands <- sort(apply(active_cands, 1,
                               function(x) paste0(x, collapse = "")))
  }
  unname(active_cands)
}

BuildCandidates <- function(active_cands, new_cands) {
  # Takes in a data frame where each row is a valid sequence of ngrams
  #     checks which of the new_cands ngram pairs are consistent with
  #     the original active_cands ngram sequence.
  #
  # Args:
  #   active_cands: data frame of ngram sequence candidates (1 candidate
  #       sequence per row)
  #   new_cands: An rx2 data frame with a new list of candidate ngram
  #       pairs that might fit in with the previous list of candidates
  #
  # Returns:
  #   Updated active_cands, with another column if valid extensions are
  #       found.

  # Get the trailing ngrams from the current candidates
  to_check <- as.vector(tail(t(active_cands), n = 1))
  # Check which of the elements in to_check are leading ngrams among the
  #     new candidates
  present <- sapply(to_check, function(x) any(x == new_cands))
  # Remove the strings that are not represented among the new candidates
  to_check <- to_check[present]
  # Now insert the new candidates where they belong
  active_cands <- active_cands[present, , drop = FALSE]
  active_cands <- cbind(active_cands, col = NA)
  num_cands <- nrow(active_cands)
  hit_list <- c()
  for (j in 1:num_cands) {
    inds <- which(new_cands[, 1] == to_check[j])
    if (length(inds) == 0) {
      hit_list <- c(hit_list, j)
      next
    }
    # If there are multiple candidates fitting with an ngram, include
    #     each /full/ string as a candidate
    extra <- length(inds) - 1
    if (extra > 0) {
      rep_inds <- c(j, (new_num_cands + 1):(new_num_cands + extra))
      to_paste <- active_cands[j, ]
      # Add the new candidates to the bottom
      for (p in 1:extra) {
        active_cands <- rbind(active_cands, to_paste)
      }
    } else {
      rep_inds <- c(j)
    }
    active_cands[rep_inds, ncol(active_cands)] <-
        as.vector(new_cands[inds, 2])
    new_num_cands <- nrow(active_cands)
  }
  # If there were some false candidates in the original set, remove them
  if (length(hit_list) > 0) {
    active_cands <- active_cands[-hit_list, , drop = FALSE]
  }
  active_cands
}

PruneCandidates <- function(active_cands, pairing, ngram_size, new_cands) {
  # Takes in a data frame where each row is a valid sequence of ngrams
  #     checks which of the new_cands ngram pairs are consistent with
  #     the original active_cands ngram sequence. This can ONLY remove
  #     candidates presented in active_cands.
  #
  # Args:
  #   active_cands: data frame of ngram sequence candidates (1 candidate
  #       sequence per row)
  #   pairing: A length-2 list storing which two ngrams are measured
  #   ngram_size: Number of characters per ngram
  #   new_cands: An rx2 data frame with a new list of candidate ngram
  #       pairs that might fit in with the previous list of candidates
  #
  # Returns:
  #   Updated active_cands, with a reduced number of rows.

  # Convert the pairing to an ngram index
  cols <- sapply(pairing, function(x) (x - 1) / ngram_size + 1)

  cands_to_check <- active_cands[, cols, drop = FALSE]
  # Find the candidates that are inconsistent with the new data
  hit_list <- sapply(1:nrow(cands_to_check), function(j) {
    to_kill <- FALSE
    if (nrow(new_cands) == 0) {
      return (TRUE)
    }
    if (!any(apply(new_cands, 1, function(x)
                   all(cands_to_check[j, , drop = FALSE] == x)))) {
      to_kill <- TRUE
    }
    to_kill
  })

  # Determine which rows are false positives
  hit_indices <- which(hit_list)
  # Remove the false positives
  if (length(hit_indices) > 0) {
    active_cands <- active_cands[-hit_indices, ]
  }
  active_cands
}

EstimateDictionary <- function(report_data, N, ngram_params, params) {
  # Takes in a list of report data and returns a list of string
  #     estimates of the dictionary.
  #
  # Args:
  #     report_data: Object containing data relevant to reports:
  #         $inds: The indices of reports collected using various pairs
  #         $cohorts: The cohort of each report
  #         $map: THe map used for all the ngrams
  #         $reports: The reports used for each ngram and full string
  #   N: the number of individuals sending reports
  #   ngram_params: Parameters related to ngram length, etc
  #   params: Parameter vector with RAPPOR noise levels, cohorts, etc
  #
  # Returns:
  #   List: list of found candidates, list of pairwise candidates

  pairwise_candidates <- FindPairwiseCandidates(report_data, N,
                                                ngram_params,
                                                params)$candidate_strs
  cat("Found the pairwise candidates. \n")
  if (is.null(pairwise_candidates)) {
    return (list())
  }
  found_candidates <- FindFeasibleStrings(pairwise_candidates,
                                          report_data$pairings,
                                          ngram_params$num_ngrams,
                                          ngram_params$ngram_size)
  cat("Found all the candidates. \n")
  list(found_candidates = found_candidates,
       pairwise_candidates = pairwise_candidates)
}

WriteKPartiteGraph <- function(conn, pairwise_candidates, pairings, num_ngrams,
                               ngram_size) {
  # Args:
  #  conn: R connection to write to.  Should be opened with mode w+.
  #  pairwise_candidates: list of matrices.  Each matrix represents a subgraph;
  #    it contains the edges between partitions i and j, so there are (k choose
  #    2) matrices.  Each matrix has dimension 2 x E, where E is the number of
  #    edges.
  #  pairings: 2 x (k choose 2) matrix of character positions.  Each row
  #    corresponds to a subgraph; it has 1-based character index of partitions
  #    i and j.
  #  num_ngrams: length of pairwise_candidates, or the number of partitions in
  #    the k-partite graph

  # File Format:
  #
  # num_partitions 3
  # ngram_size 2
  # 0.ab 1.cd
  # 0.ab 2.ef
  #
  # The first line specifies the number of partitions (k).
  # The remaining lines are edges, where each node is <partition>.<bigram>.
  #
  # Partitions are numbered from 0.  The partition of the left node will be
  # less than the partition of the right node.

  # First two lines are metadata
  cat(sprintf('num_partitions %d\n', num_ngrams), file = conn)
  cat(sprintf('ngram_size %d\n', ngram_size), file = conn)

  for (i in 1:length(pairwise_candidates)) {
    # The two pairwise_candidates for this subgraph.
    # Turn 1-based character positions into 0-based partition numbers,
    # e.g. (3, 5) -> (1, 2)

    pos1 <- pairings[[i, 1]]
    pos2 <- pairings[[i, 2]]
    part1 <- (pos1 - 1) / ngram_size
    part2 <- (pos2 - 1) / ngram_size
    cat(sprintf("Writing partition (%d, %d)\n", part1, part2))

    p <- pairwise_candidates[[i]]
    # each row is an edge
    for (j in 1:nrow(p)) {
      n1 <- p[[j, 1]]
      n2 <- p[[j, 2]]
      line <- sprintf('edge %d.%s %d.%s\n', part1, n1, part2, n2)
      # NOTE: It would be faster to preallocate 'lines', but we would have to
      # make a two passes through pairwise_candidates.
      cat(line, file = conn)
    }
  }
}

