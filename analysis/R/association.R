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

library(parallel)  # mclapply

source.rappor <- function(rel_path)  {
  abs_path <- paste0(Sys.getenv("RAPPOR_REPO", ""), rel_path)
  source(abs_path)
}

source.rappor("analysis/R/util.R")  # for Log
source.rappor("analysis/R/decode.R")  # for ComputeCounts

#
# Tools used to estimate variable distributions of up to three variables
#     in RAPPOR. This contains the functions relevant to estimating joint
#     distributions.

GetOtherProbs <- function(counts, map_by_cohort, marginal, params, pstar,
                          qstar) {
  # Computes the marginal for the "other" category.
  #
  # Args:
  #   counts: m x (k+1) matrix with counts of each bit for each
  #       cohort (m=#cohorts total, k=# bits in bloom filter), first column
  #       stores the total counts
  #   map_by_cohort: list of matrices encoding locations of hashes for each
  #       string "other" category)
  #   marginal: object containing the estimated frequencies of known strings
  #       as well as the strings themselves, variance, etc.
  #   params: RAPPOR encoding parameters
  #
  # Returns:
  #   List of vectors of probabilities that each bit was set by the "other"
  #   category.  The list is indexed by cohort.

  N <- sum(counts[, 1])

  # Counts of known strings to remove from each cohort.
  known_counts <- ceiling(marginal$proportion * N / params$m)
  sum_known <- sum(known_counts)

  # Select only the strings we care about from each cohort.
  # NOTE: drop = FALSE necessary if there is one candidate
  candidate_map <- lapply(map_by_cohort, function(map_for_cohort) {
    map_for_cohort[, marginal$string, drop = FALSE]
  })

  # If no strings were found, all nonzero counts were set by "other"
  if (length(marginal) == 0) {
    probs_other <- apply(counts, 1, function(cohort_row) {
      cohort_row[-1] / cohort_row[1]
    })
    return(as.list(as.data.frame(probs_other)))
  }

  # Counts set by known strings without noise considerations.
  known_counts_by_cohort <- sapply(candidate_map, function(map_for_cohort) {
    as.vector(as.matrix(map_for_cohort) %*% known_counts)
  })

  # Protect against R's matrix/vector confusion.  This ensures
  # known_counts_by_cohort is a matrix in the k=1 case.
  dim(known_counts_by_cohort) <- c(params$m, params$k)

  # Counts set by known vals zero bits adjusting by p plus true bits
  # adjusting by q.
  known_counts_by_cohort <- (sum_known - known_counts_by_cohort) * pstar +
                            known_counts_by_cohort * qstar

  # Add the left hand sums to make it a m x (k+1) "counts" matrix
  known_counts_by_cohort <- cbind(sum_known, known_counts_by_cohort)

  # Counts set by the "other" category.
  reduced_counts <- counts - known_counts_by_cohort
  reduced_counts[reduced_counts < 0] <- 0
  probs_other <- apply(reduced_counts, 1, function(cohort_row) {
    cohort_row[-1] / cohort_row[1]
  })

  # Protect against R's matrix/vector confusion.
  dim(probs_other) <- c(params$k, params$m)

  probs_other[probs_other > 1] <- 1
  probs_other[is.nan(probs_other)] <- 0
  probs_other[is.infinite(probs_other)] <- 0

  # Convert it from a k x m matrix to a list indexed by m cohorts.
  # as.data.frame makes each cohort a column, which can be indexed by
  # probs_other[[cohort]].
  result <- as.list(as.data.frame(probs_other))

  result
}

GetCondProbBooleanReports <- function(reports, pstar, qstar, num_cores) {
  # Compute conditional probabilities given a set of Boolean reports.
  #
  # Args:
  #   reports: RAPPOR reports as a list of bit arrays (of length 1, because
  #   this is a boolean report)
  #   pstar, qstar: standard params computed from from rappor parameters
  #   num_cores: number of cores to pass to mclapply to parallelize apply
  #
  # Returns:
  #   Conditional probability of all boolean reports corresponding to
  #   candidates (TRUE, FALSE)

  # The values below are p(report=1|value=TRUE), p(report=1|value=FALSE)
  cond_probs_for_1 <- c(qstar, pstar)
  # The values below are p(report=0|value=TRUE), p(report=0|value=FALSE)
  cond_probs_for_0 <- c(1 - qstar,  1 - pstar)

  cond_report_dist <- mclapply(reports, function(report) {
    if (report[[1]] == 1) {
      cond_probs_for_1
    } else {
      cond_probs_for_0
    }
  }, mc.cores = num_cores)
  cond_report_dist
}

GetCondProbStringReports <- function(reports, cohorts, map, m, pstar, qstar,
                                     marginal, prob_other = NULL, num_cores) {
  # Wrapper around GetCondProb. Given a set of reports, cohorts, map and
  # parameters m, p*, and q*, it first computes bit indices by cohort, and
  # then applies GetCondProb individually to each report.
  #
  # Args:
  #   reports: RAPPOR reports as a list of bit arrays
  #   cohorts: cohorts corresponding to these reports as a list
  #   map: map file
  #   m, pstar, qstar: standard params computed from from rappor parameters
  #   marginal: list containing marginal estimates (output of Decode)
  #   prob_other: vector of length k, indicating how often each bit in the
  #     Bloom filter was set by a string in the "other" category.
  #
  # Returns:
  #   Conditional probability of all reports given each of the strings in
  #   marginal$string

  # Get bit indices that are set per candidate per cohort
  bit_indices_by_cohort <- lapply(1:m, function(cohort) {
    map_for_cohort <- map$map_by_cohort[[cohort]]
    # Find the bits set by the candidate strings
    bit_indices <- lapply(marginal$string, function(x) {
      which(map_for_cohort[, x])
    })
    bit_indices
  })

  # Apply GetCondProb over all reports
  cond_report_dist <- mclapply(seq(length(reports)), function(i) {
    cohort <- cohorts[i]
    #Log('Report %d, cohort %d', i, cohort)
    bit_indices <- bit_indices_by_cohort[[cohort]]
    GetCondProb(reports[[i]], pstar, qstar, bit_indices,
                prob_other = prob_other[[cohort]])
  }, mc.cores = num_cores)
  cond_report_dist
}


GetCondProb <- function(report, pstar, qstar, bit_indices, prob_other = NULL) {
  # Given the observed bit array, estimate P(report | true value).
  # Probabilities are estimated for all truth values.
  #
  # Args:
  #   report: A single observed RAPPOR report (binary vector of length k).
  #   params: RAPPOR parameters.
  #   bit_indices: list with one entry for each candidate.  Each entry is an
  #     integer vector of length h, specifying which bits are set for the
  #     candidate in the report's cohort.
  #   prob_other: vector of length k, indicating how often each bit in the
  #     Bloom filter was set by a string in the "other" category.
  #
  # Returns:
  #   Conditional probability of report given each of the strings in
  #       candidate_strings
  ones <- sum(report)
  zeros <- length(report) - ones
  probs <- ifelse(report == 1, pstar, 1 - pstar)

  # Find the likelihood of report given each candidate string
  prob_obs_vals <- sapply(bit_indices, function(x) {
    prod(c(probs[-x], ifelse(report[x] == 1, qstar, 1 - qstar)))
  })

  # Account for the "other" category
  if (!is.null(prob_other)) {
    prob_other <- prod(c(prob_other[which(report == 1)],
                         (1 - prob_other)[which(report == 0)]))
    c(prob_obs_vals, prob_other)
  } else {
    prob_obs_vals
  }
}

UpdatePij <- function(pij, cond_prob) {
  # Update the probability matrix based on the EM algorithm.
  #
  # Args:
  #   pij: conditional distribution of x (vector)
  #   cond_prob: conditional distribution computed previously
  #
  # Returns:
  #   Updated pijs from em algorithm (maximization)

  # NOTE: Not using mclapply here because we have a faster C++ implementation.
  # mclapply spawns multiple processes, and each process can take up 3 GB+ or 5
  # GB+ of memory.
  wcp <- lapply(cond_prob, function(x) {
    z <- x * pij
    z <- z / sum(z)
    z[is.nan(z)] <- 0
    z
  })
  Reduce("+", wcp) / length(wcp)
}

ComputeVar <- function(cond_prob, est) {
  # Computes the variance of the estimated pij's.
  #
  # Args:
  #   cond_prob: conditional distribution computed previously
  #   est: estimated pij's
  #
  # Returns:
  #   Variance of the estimated pij's

  inform <- Reduce("+", lapply(cond_prob, function(x) {
    (outer(as.vector(x), as.vector(x))) / (sum(x * est))^2
  }))
  var_cov <- solve(inform)
  sd <- matrix(sqrt(diag(var_cov)), dim(cond_prob[[1]]))
  list(var_cov = var_cov, sd = sd, inform = inform)
}

EM <- function(cond_prob, starting_pij = NULL, estimate_var = FALSE,
               max_em_iters = 1000, epsilon = 10^-6, verbose = FALSE) {
  # Performs estimation.
  #
  # Args:
  #   cond_prob: conditional distribution computed previously
  #   starting_pij: estimated pij's
  #   estimate_var: flags whether we should estimate the variance
  #       of our computed distribution
  #   max_em_iters: maximum number of EM iterations
  #   epsilon: convergence parameter
  #   verbose: flags whether to display error data
  #
  # Returns:
  #   Estimated pij's, variance, error params

  pij <- list()
  state_space <- dim(cond_prob[[1]])
  if (is.null(starting_pij)) {
    pij[[1]] <- array(1 / prod(state_space), state_space)
  } else {
    pij[[1]] <- starting_pij
  }

  i <- 0  # visible outside loop
  if (nrow(pij[[1]]) > 0) {
    # Run EM
    for (i in 1:max_em_iters) {
      pij[[i + 1]] <- UpdatePij(pij[[i]], cond_prob)
      dif <- max(abs(pij[[i + 1]] - pij[[i]]))
      if (dif < epsilon) {
        break
      }
      Log('EM iteration %d, dif = %e', i, dif)
    }
  }
  # Compute the variance of the estimate.
  est <- pij[[length(pij)]]
  if (estimate_var) {
    var_cov <- ComputeVar(cond_prob, est)
    sd <- var_cov$sd
    inform <- var_cov$inform
    var_cov <- var_cov$var_cov
  } else {
    var_cov <- NULL
    inform <- NULL
    sd <- NULL
  }
  list(est = est, sd = sd, var_cov = var_cov, hist = pij, num_em_iters = i)
}

TestIndependence <- function(est, inform) {
  # Tests the degree of independence between variables.
  #
  # Args:
  #   est: esimated pij values
  #   inform: information matrix
  #
  # Returns:
  #   Chi-squared statistic for whether two variables are independent

  expec <- outer(apply(est, 1, sum), apply(est, 2, sum))
  diffs <- matrix(est - expec, ncol = 1)
  stat <- t(diffs) %*% inform %*% diffs
  df <- (nrow(est) - 1) * (ncol(est) - 1)
  list(stat = stat, pval = pchisq(stat, df, lower = FALSE))
}

UpdateJointConditional <- function(cond_report_dist, joint_conditional = NULL) {
  # Updates the joint conditional  distribution of d variables, where
  #     num_variables is chosen by the client. Since variables are conditionally
  #     independent of one another, this is basically an outer product.
  #
  # Args:
  #   joint_conditional: The current state of the joint conditional
  #       distribution. This is a list with as many elements as there
  #       are reports.
  #   cond_report_dist: The conditional distribution of variable x, which will
  #       be outer-producted with the current joint conditional.
  #
  # Returns:
  #   A list of same length as joint_conditional containing the joint
  #       conditional distribution of all variables. If I want
  #       P(X'=x',Y=y'|X=x,Y=y), I will look at
  #       joint_conditional[x,x',y,y'].

  if (is.null(joint_conditional)) {
    lapply(cond_report_dist, function(x) array(x))
  } else {
    mapply("outer", joint_conditional, cond_report_dist,
           SIMPLIFY = FALSE)
  }
}

ComputeDistributionEM <- function(reports, report_cohorts, maps,
                                  ignore_other = FALSE,
                                  params = NULL,
                                  params_list = NULL,
                                  marginals = NULL,
                                  estimate_var = FALSE,
                                  num_cores = 10,
                                  em_iter_func = EM,
                                  max_em_iters = 1000) {
  # Computes the distribution of num_variables variables, where
  #     num_variables is chosen by the client, using the EM algorithm.
  #
  # Args:
  #   reports: A list of num_variables elements, each a 2-dimensional array
  #       containing the counts of each bin for each report
  #   report_cohorts: A num_variables-element list; the ith element is an array
  #       containing the cohort of jth report for ith variable.
  #   maps: A num_variables-element list containing the map for each variable
  #   ignore_other: A boolean describing whether to compute the "other" category
  #   params: RAPPOR encoding parameters.  If set, all variables are assumed to
  #       be encoded with these parameters.
  #   params_list: A list of num_variables elements, each of which is the
  #       RAPPOR encoding parameters for a variable (a list itself).  If set,
  #       it must be the same length as 'reports'.
  #   marginals: List of estimated marginals for each variable
  #   estimate_var: A flag telling whether to estimate the variance.
  #   em_iter_func: Function that implements the iterative EM algorithm.

  # Handle the case that the client wants to find the joint distribution of too
  # many variables.
  num_variables <- length(reports)

  if (is.null(params) && is.null(params_list)) {
    stop("Either params or params_list must be passed")
  }

  Log('Computing joint conditional')

  # Compute the counts for each variable and then do conditionals.
  joint_conditional = NULL
  found_strings <- list()

  for (j in (1:num_variables)) {
    Log('Processing var %d', j)

    var_report <- reports[[j]]
    var_cohort <- report_cohorts[[j]]
    var_map <- maps[[j]]
    if (!is.null(params)) {
      var_params <- params
    } else {
      var_params <- params_list[[j]]
    }

    var_counts <- NULL
    if (is.null(marginals)) {
      Log('\tSumming bits to gets observed counts')
      var_counts <- ComputeCounts(var_report, var_cohort, var_params)

      Log('\tDecoding marginal')
      marginal <- Decode(var_counts, var_map$all_cohorts_map, var_params,
                         quiet = TRUE)$fit
      Log('\tMarginal for var %d has %d values:', j, nrow(marginal))
      print(marginal[, c('estimate', 'proportion')])  # rownames are the string
      cat('\n')

      if (nrow(marginal) == 0) {
        Log('ERROR: Nothing decoded for variable %d', j)
        return (NULL)
      }
    } else {
      marginal <- marginals[[j]]
    }
    found_strings[[j]] <- marginal$string

    p <- var_params$p
    q <- var_params$q
    f <- var_params$f
    # pstar and qstar needed to compute other probabilities as well as for
    # inputs to GetCondProb{Boolean, String}Reports subsequently
    pstar <- (1 - f / 2) * p + (f / 2) * q
    qstar <- (1 - f / 2) * q + (f / 2) * p
    k <- var_params$k

    # Ignore other probability if either ignore_other is set or k == 1
    # (Boolean RAPPOR)
    if (ignore_other || (k == 1)) {
      prob_other <- vector(mode = "list", length = var_params$m)
    } else {
      # Compute the probability of the "other" category
      if (is.null(var_counts)) {
        var_counts <- ComputeCounts(var_report, var_cohort, var_params)
      }
      prob_other <- GetOtherProbs(var_counts, var_map$map_by_cohort, marginal,
                                  var_params, pstar, qstar)
      found_strings[[j]] <- c(found_strings[[j]], "Other")
    }

    # Get the joint conditional distribution
    Log('\tGetCondProb for each report (%d cores)', num_cores)

    # TODO(pseudorandom): check RAPPOR type more systematically instead of by
    # checking if k == 1
    if (k == 1) {
      cond_report_dist <- GetCondProbBooleanReports(var_report, pstar, qstar,
                                                    num_cores)
    } else {
      cond_report_dist <- GetCondProbStringReports(var_report,
                                var_cohort, var_map, var_params$m, pstar, qstar,
                                marginal, prob_other, num_cores)
    }

    Log('\tUpdateJointConditional')

    # Update the joint conditional distribution of all variables
    joint_conditional <- UpdateJointConditional(cond_report_dist,
                                                joint_conditional)
  }

  N <- length(joint_conditional)
  dimensions <- dim(joint_conditional[[1]])
  # e.g. 2 x 3
  dimensions_str <- paste(dimensions, collapse = ' x ')
  total_entries <- prod(c(N, dimensions))

  Log('Starting EM with N = %d matrices of size %s (%d entries)',
      N, dimensions_str, total_entries)

  start_time <- proc.time()[['elapsed']]

  # Run expectation maximization to find joint distribution
  em <- em_iter_func(joint_conditional, max_em_iters=max_em_iters,
                     epsilon = 10 ^ -6, verbose = FALSE,
                     estimate_var = estimate_var)

  em_elapsed_time <- proc.time()[['elapsed']] - start_time

  dimnames(em$est) <- found_strings
  # Return results in a usable format
  list(fit = em$est,
       sd = em$sd,
       em_elapsed_time = em_elapsed_time,
       num_em_iters = em$num_em_iters,
       # This last field is implementation-specific; it can be used for
       # interactive debugging.
       em = em)
}
