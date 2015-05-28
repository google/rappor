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
# Tools used to estimate variable distributions of up to three variables
#     in RAPPOR. This contains the functions relevant to estimating joint
#     distributions.

GetOtherProbs <- function(counts, map, marginal, params) {
  # Computes the marginal for the "other" category.
  #
  # Args:
  #   counts: mx(k+1) matrix with counts of each bit for each
  #       cohort (m=#cohorts total, k=# bits in bloom filter), first row
  #       stores the total counts
  #   map: list of matrices encoding locations of hashes for each string
  #       "other" category)
  #   marginal: object containing the estimated frequencies of known strings
  #       as well as the strings themselves, variance, etc.
  #   params: System parameters
  #
  # Returns:
  #   Vector of probabilities that each bit was set by the "other" category

  N <- sum(counts[, 1])
  f <- params$f
  q <- params$q
  p <- params$p

  # List of known strings that were measured in the marginal.
  candidate_strings <- marginal$strings

  # Counts to remove from each cohort.
  top_counts <- ceiling(marginal$proportion * N / params$m)
  sum_top <- sum(top_counts)
  candidate_map <- lapply(map, function(x) x[, candidate_strings])

  # Counts set by known strings without noise considerations.
  if (length(marginal) > 0) {
    top_counts_cohort <- t(sapply(candidate_map, function(x) {
      as.vector(as.matrix(x) %*% top_counts)
    }))
  } else {
    # If no strings were found, all nonzero counts were set by "other"
    props_other <- apply(counts, 1, function(x) x[-1] / x[1])
    return(as.list(as.data.frame(props_other)))
  }

  # Counts set by top vals zero bits adjusting by p plus true bits
  # adjusting by q.
  qstar <- (1 - f / 2) * q + (f / 2) * p
  pstar <- (1 - f / 2) * p + (f / 2) * q
  top_counts_cohort <- (sum_top - top_counts_cohort) * pstar +
      top_counts_cohort * qstar
  top_counts_cohort <- cbind(sum_top, top_counts_cohort)

  # Counts set by the "other" category.
  reduced_counts <- counts - top_counts_cohort
  reduced_counts[reduced_counts < 0] <- 0
  props_other <- apply(reduced_counts, 1, function(x) x[-1] / x[1])
  props_other[props_other > 1] <- 1
  props_other[is.nan(props_other)] <- 0
  props_other[is.infinite(props_other)] <- 0
  as.list(as.data.frame(props_other))
}

GetCondProb <- function(report, candidate_strings, params, map,
                        prob_other = NULL) {
  # Given the observed bit array, estimate P(report | true value).
  # Probabilities are estimated for all truth values.
  #
  # Args:
  #   report: a single observed RAPPOR report (binary vector of length k)
  #   candidate_strings: vector of strings in the dictionary (i.e. not the
  #       "other" category)
  #   params: System parameters
  #   map: list of matrices encoding locations of hashes for each string
  #   prob_other: vector of length k, indicating how often each bit in the
  #       Bloom filter was set by a string in the "other" category
  #
  # Returns:
  #   Conditional probability of report given each of the strings in
  #       candidate_strings

  p <- params$p
  q <- params$q
  f <- params$f
  ones <- sum(report)
  zeros <- length(report) - ones

  qstar <- (1 - f / 2) * q + (f / 2) * p
  pstar <- (1 - f / 2) * p + (f / 2) * q
  probs <- ifelse(report == 1, pstar, 1 - pstar)

  # Find the bits set by the candidate strings
  inds <- lapply(candidate_strings, function(x)
                 which(map[, x]))

  # Find the likelihood of report given each candidate string
  prob_obs_vals <- sapply(inds, function(x) {
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

GetJointConditionalProb <- function(cond_x, cond_y) {
  # Given the conditional probability functions for x and y, compute the
  #     joint conditional distribution P(X',Y'|X,Y)
  #
  # Args:
  #   cond_x: conditional distribution of x (vector)
  #   cond_y: conditional distribution of y (vector)
  #
  # Returns:
  #   Joint conditional distribution (i.e. outer product of
  #      distributions.

  mapply("outer", cond_x, cond_y, SIMPLIFY = FALSE)
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

  wcp <- lapply(cond_prob, function(x) {
    z <- x * pij
    z <- z / sum(z)
    z[is.nan(z)] <- 0
    z })
  Reduce("+", wcp) / length(wcp)
}

NLL <- function(pij, cond_prob) {
  # Update the probability matrix based on the EM algorithm.
  #
  # Args:
  #   pij: conditional distribution of x (vector)
  #   cond_prob: conditional distribution computed previously
  #
  # Returns:
  #   Updated pijs from em algorithm (expectation)

  sum(sapply(cond_prob, function(x) -log(sum(x * pij))))
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
               max_iter = 1000, epsilon = 10^-6, verbose = FALSE) {
  # Performs estimation.
  #
  # Args:
  #   cond_prob: conditional distribution computed previously
  #   starting_pij: estimated pij's
  #   estimate_var: flags whether we should estimate the variance
  #       of our computed distribution
  #   max_iter: maximum number of EM iterations
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

  if (nrow(pij[[1]]) > 0) {
    # Run EM
    for (i in 1:max_iter) {
      pij[[i + 1]] <- UpdatePij(pij[[i]], cond_prob)
      dif <- max(abs(pij[[i + 1]] - pij[[i]]))
      if (dif < epsilon) {
        break
      }
      if (verbose) {
        cat(i, dif, "\n")
      }
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
  list(est = est, sd = sd, var_cov = var_cov, hist = pij)
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

ComputeDistributionEM <- function(reports, report_cohorts,
                                  maps, ignore_other = FALSE,
                                  params,
                                  marginals = NULL,
                                  estimate_var = FALSE) {
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
  #   params: A list of parameters for the problem
  #   marginals: List of estimated marginals for each variable
  #   estimate_var: A flag telling whether to estimate the variance.


  # Handle the case that the client wants to find the joint distribution of
  #     too many variables.
  num_variables <- length(reports)
  if (num_variables > 4) {
    cat("This is too many variables to compare, exiting now.")
    return -1
  }

  # Compute the counts for each variable and then do conditionals.
  joint_conditional = NULL
  found_strings <- list()

  for (j in (1:num_variables)) {
    variable_report <- reports[[j]]
    variable_cohort <- report_cohorts[[j]]
    map <- maps[[j]]

    # Compute the probability of the "other" category
    variable_counts <- NULL
    if (is.null(marginals)) {
      variable_counts <- ComputeCounts(variable_report, variable_cohort, params)
      marginal <- Decode(variable_counts, map$rmap, params, quiet = TRUE)$fit
      if (nrow(marginal) == 0) {
        return (NULL)
      }
    } else {
      marginal <- marginals[[j]]
    }
    found_strings[[j]] <- marginal$strings

    if (ignore_other) {
      prob_other <- vector(mode = "list", length = params$m)
    } else {
      if (is.null(variable_counts)) {
        variable_counts <- ComputeCounts(variable_report, variable_cohort,
                                         params)
      }
      prob_other <- GetOtherProbs(variable_counts, map$map, marginal,
                                  params)
      found_strings[[j]] <- c(found_strings[[j]], "Other")
    }

    # Get the joint conditional distribution
    cond_report_dist <- lapply(seq(length(variable_report)), function(i) {
      idx <- variable_cohort[i]
      rep <- GetCondProb(variable_report[[i]],
                         candidate_strings = rownames(marginal),
                         params = params,
                         map$map[[idx]],
                         prob_other[[idx]])
      rep
    })

    # Update the joint conditional distribution of all variables
    joint_conditional <- UpdateJointConditional(cond_report_dist,
                                                joint_conditional)
  }

  # Run expectation maximization to find joint distribution
  em <- EM(joint_conditional, epsilon = 10 ^ -6, verbose = FALSE,
           estimate_var = estimate_var)
  dimnames(em$est) <- found_strings
  # Return results in a usable format
  list(fit = em$est, sd = em$sd, em = em)

}
