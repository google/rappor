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
# This library implements the RAPPOR marginal decoding algorithms using LASSO.

library(glmnet)

source('analysis/R/alternative.R')

EstimateBloomCounts <- function(params, obs_counts) {
  # Estimates the number of times each bit in each cohort was set in original
  # Bloom filters.
  #
  # Input:
  #    params: a list of RAPPOR parameters:
  #            k - size of a Bloom filter
  #            h - number of hash functions
  #            m - number of cohorts
  #            p - P(IRR = 1 | PRR = 0)
  #            q - P(IRR = 1 | PRR = 1)
  #            f - Proportion of bits in the Bloom filter that are set randomly
  #                to 0 or 1 regardless of the underlying true bit value
  #    obs_counts: a matrix of size m by (k + 1). Column one contains sample
  #                sizes for each cohort. Other counts indicated how many times
  #                each bit was set in each cohort.
  #
  # Output:
  #    ests: a matrix of size m by k with estimated counts for the probability
  #          of each bit set to 1 in the true Bloom filter.
  #    std: standard deviation of the estimates.

  p <- params$p
  q <- params$q
  f <- params$f
  m <- params$m

  stopifnot(m == nrow(obs_counts), params$k + 1 == ncol(obs_counts))

  p11 <- q * (1 - f/2) + p * f / 2  # probability of a true 1 reported as 1
  p01 <- p * (1 - f/2) + q * f / 2  # probability of a true 0 reported as 1

  p2 <- p11 - p01  # == (1 - f) * (q - p)

  ests <- apply(obs_counts, 1, function(x) {
      N <- x[1]  # sample size for the cohort
      v <- x[-1]  # counts for individual bits
      (v - p01 * N) / p2  # unbiased estimator for individual bits'
                          # true counts. It can be negative or
                          # exceed the total.
    })

  total <- sum(obs_counts[,1])

  variances <- apply(obs_counts, 1, function(x) {
      N <- x[1]
      v <- x[-1]
      p_hats <- (v - p01 * N) / (N * p2)  # expectation of a true 1
      p_hats <- pmax(0, pmin(1, p_hats))  # clamp to [0,1]
      r <- p_hats * p11 + (1 - p_hats) * p01  # expectation of a reported 1
      N * r * (1 - r) / p2^2  # variance of the binomial
     })

  # Transform counts from absolute values to fractional, removing bias due to
  #      variability of reporting between cohorts.
  ests <- apply(ests, 1, function(x) x / obs_counts[,1])
  stds <- apply(variances^.5, 1, function(x) x / obs_counts[,1])

  # Some estimates may be set to infinity, e.g. if f=1. We want to
  #     account for this possibility, and set the corresponding counts
  #     to 0.
  ests[abs(ests) == Inf] <- 0

  list(estimates = ests, stds = stds)
}

FitLasso <- function(X, Y, intercept = TRUE) {
  # Fits a Lasso model to select a subset of columns of X.
  #
  # Input:
  #    X: a design matrix of size km by M (the number of candidate strings).
  #    Y: a vector of size km with estimated counts from EstimateBloomCounts().
  #    intercept: whether to fit with intercept or not.
  #
  # Output:
  #    a vector of size ncol(X) of coefficients.

  # TODO(mironov): Test cv.glmnet instead of glmnet
  mod <- try(glmnet(X, Y, standardize = FALSE, intercept = intercept,
                    lower.limits = 0,  # outputs are non-negative
                    # Cap the number of non-zero coefficients to 500 or
                    # 80% of the length of Y, whichever is less. The 500 cap
                    # is for performance reasons, 80% is to avoid overfitting.
                    pmax = min(500, length(Y) * .8)),
             silent = TRUE)

  # If fitting fails, return an empty data.frame.
  if (class(mod)[1] == "try-error") {
    coefs <- setNames(rep(0, ncol(X)), colnames(X))
  } else {
    coefs <- coef(mod)
    coefs <- coefs[-1, ncol(coefs), drop = FALSE]  # coefs[1] is the intercept
  }
  coefs
}

PerformInference <- function(X, Y, N, mod, params, alpha, correction) {
  m <- params$m
  p <- params$p
  q <- params$q
  f <- params$f
  h <- params$h

  q2 <- .5 * f * (p + q) + (1 - f) * q
  p2 <- .5 * f * (p + q) + (1 - f) * p
  resid_var <- p2 * (1 - p2) * (N / m) / (q2 - p2)^2

  # Total Sum of Squares (SS).
  TSS <- sum((Y - mean(Y))^2)
  # Error Sum of Squares (ESS).
  ESS <- resid_var * nrow(X)

  betas <- matrix(mod$coefs, ncol = 1)

#   mod_var <- summary(mod$fit)$sigma^2
#   betas_sd <- rep(sqrt(max(resid_var, mod_var) / (m * h)), length(betas))
#
#   z_values <- betas / betas_sd
#
#   # 1-sided t-test.
#   p_values <- pnorm(z_values, lower = FALSE)

  fit <- data.frame(String = colnames(X), Estimate = betas,
                    SD = mod$stds, # z_stat = z_values, pvalue = p_values,
                    stringsAsFactors = FALSE)

#   if (correction == "FDR") {
#     fit <- fit[order(fit$pvalue, decreasing = FALSE), ]
#     ind <- which(fit$pvalue < (1:nrow(fit)) * alpha / nrow(fit))
#     if (length(ind) > 0) {
#       fit <- fit[1:max(ind), ]
#     } else {
#       fit <- fit[numeric(0), ]
#     }
#   } else {
#     fit <- fit[fit$p < alpha, ]
#   }

  fit <- fit[order(fit$Estimate, decreasing = TRUE), ]

  if (nrow(fit) > 0) {
    str_names <- fit$String
    str_names <- str_names[!is.na(str_names)]
    if (length(str_names) > 0 && length(str_names) < nrow(X)) {
      this_data <- as.data.frame(as.matrix(X[, str_names]))
      Y_hat <- predict(lm(Y ~ ., data = this_data))
      RSS <- sum((Y_hat - mean(Y))^2)
    } else {
      RSS <- NA
    }
  } else {
    RSS <- 0
  }

  USS <- TSS - ESS - RSS
  SS <- c(RSS, USS, ESS) / TSS

  list(fit = fit, SS = SS, resid_sigma = sqrt(resid_var))
}

ComputePrivacyGuarantees <- function(params, alpha, N) {
  # Compute privacy parameters and guarantees.
  p <- params$p
  q <- params$q
  f <- params$f
  h <- params$h

  q2 <- .5 * f * (p + q) + (1 - f) * q
  p2 <- .5 * f * (p + q) + (1 - f) * p

  exp_e_one <- ((q2 * (1 - p2)) / (p2 * (1 - q2)))^h
  if (exp_e_one < 1) {
    exp_e_one <- 1 / exp_e_one
  }
  e_one <- log(exp_e_one)

  exp_e_inf <- ((1 - .5 * f) / (.5 * f))^(2 * h)
  e_inf <- log(exp_e_inf)

  std_dev_counts <- sqrt(p2 * (1 - p2) * N) / (q2 - p2)
  detection_freq <- qnorm(1 - alpha) * std_dev_counts / N

  privacy_names <- c("Effective p", "Effective q", "exp(e_1)",
                     "e_1", "exp(e_inf)", "e_inf", "Detection frequency")
  privacy_vals <- c(p2, q2, exp_e_one, e_one, exp_e_inf, e_inf, detection_freq)

  privacy <- data.frame(parameters = privacy_names,
                        values = privacy_vals)
  privacy
}

FitDistribution <- function(estimates_stds, map, quiet = FALSE) {
  # Find a distribution over rows of map that approximates estimates_stds best
  #
  # Input:
  #   estimates_stds: a list of two m x k matrices, one for estimates, another
  #                   for standard errors
  #   map           : an (m * k) x S boolean matrix
  #
  # Output:
  #   a float vector of length S, so that a distribution over map's rows sampled
  #   according to this vector approximates estimates

  S <- ncol(map)  # total number of candidates

  support_coefs <- 1:S

  if (S > length(estimates_stds$estimates) * .8) {
    # the system is close to being underdetermined
    lasso <- FitLasso(map, as.vector(t(estimates_stds$estimates)))

    # Select non-zero coefficients.
    support_coefs <- which(lasso > 0)

    if(!quiet)
      cat("LASSO selected ", length(support_coefs), " non-zero coefficients.\n")
  }

  coefs <- setNames(rep(0, S), colnames(map))

  if(length(support_coefs) > 0) {  # LASSO may return an empty list
    constrained_coefs <- ConstrainedLinModel(map[, support_coefs, drop = FALSE],
                                             estimates_stds)

    coefs[support_coefs] <- constrained_coefs
  }

  coefs
}

Resample <- function(e) {
  # Simulate resampling of the Bloom filter estimates by adding Gaussian noise
  # with estimated standard deviation.
  estimates <- matrix(mapply(function(x, y) x + rnorm(1, 0, y),
                             e$estimates, e$stds),
                             nrow = nrow(e$estimates), ncol = ncol(e$estimates))
  stds <- e$stds * 2^.5

  list(estimates = estimates, stds = stds)
}

Decode <- function(counts, map, params, alpha = 0.05,
                   correction = c("Bonferroni"), quiet = FALSE, ...) {
  k <- params$k
  p <- params$p
  q <- params$q
  f <- params$f
  h <- params$h
  m <- params$m

  S <- ncol(map)  # total number of candidates

  N <- sum(counts[, 1])

  filter_cohorts <- which(counts[, 1] != 0)  # exclude cohorts with zero reports

  # stretch cohorts to bits
  filter_bits <- as.vector(
    t(matrix(1:nrow(map), nrow = m, byrow = TRUE)[filter_cohorts,]))

  es <- EstimateBloomCounts(params, counts)

  estimates_stds_filtered <-
    list(estimates = es$estimates[filter_cohorts, , drop = FALSE],
         stds = es$stds[filter_cohorts, , drop = FALSE])

  coefs_all <- vector()

  # Run the fitting procedure several times (5 seems to be sufficient and not
  # too many) to estimate standard deviation of the output.
  for(r in 1:5) {
    if(r > 1)
      e <- Resample(estimates_stds_filtered)
    else
      e <- estimates_stds_filtered

    coefs_all <- rbind(coefs_all,
                       FitDistribution(e, map[filter_bits, , drop = FALSE],
                                       quiet))
  }

  coefs_ssd <- N * apply(coefs_all, 2, sd)  # compute sample standard deviations
  coefs_ave <- N * apply(coefs_all, 2, mean)

  # Only select coefficients more than two standard deviations from 0. May
  # inflate empirical SD of the estimates.
  reported <- which(coefs_ave > 1E-6 + 2 * coefs_ssd)

  mod <- list(coefs = coefs_ave[reported], stds = coefs_ssd[reported])

  if (correction == "Bonferroni") {
    alpha <- alpha / S
  }

  inf <- PerformInference(map[filter_bits, reported, drop = FALSE],
                          as.vector(t(estimates_stds_filtered$estimates)),
                          N, mod, params, alpha,
                          correction)
  fit <- inf$fit
  # If this is a basic RAPPOR instance, just use the counts for the estimate
  #     (Check if the map is diagonal to tell if this is basic RAPPOR.)
  if (sum(map) == sum(diag(map))) {
    fit$Estimate <- colSums(counts)[-1]
  }

  # Estimates from the model are per instance so must be multipled by h.
  # Standard errors are also adjusted.
  fit$Total_Est <- floor(fit$Estimate)
  fit$Total_SD <- floor(fit$SD)
  fit$Prop <- fit$Total_Est / N
  fit$LPB <- fit$Prop - 1.96 * fit$Total_SD / N
  fit$UPB <- fit$Prop + 1.96 * fit$Total_SD / N

  fit <- fit[, c("String", "Total_Est", "Total_SD", "Prop", "LPB", "UPB")]
  colnames(fit) <- c("strings", "estimate", "std_dev", "proportion",
                     "lower_bound", "upper_bound")

  # Compute summary of the fit.
  parameters =
      c("Candidate strings", "Detected strings",
        "Sample size (N)", "Discovered Prop (out of N)",
        "Explained Variance", "Missing Variance", "Noise Variance",
        "Theoretical Noise Std. Dev.")
  values <- c(S, nrow(fit), N, round(sum(fit[, 2]) / N, 3),
              round(inf$SS, 3),
              round(inf$resid_sigma, 3))
  res_summary <- data.frame(parameters = parameters, values = values)

  privacy <- ComputePrivacyGuarantees(params, alpha, N)
  params <- data.frame(parameters =
                       c("k", "h", "m", "p", "q", "f", "N", "alpha"),
                       values = c(k, h, m, p, q, f, N, alpha))

  list(fit = fit, summary = res_summary, privacy = privacy, params = params,
       lasso = NULL, ests = as.vector(t(estimates_stds_filtered$estimates)),
       counts = counts[, -1], resid = NULL)
}

ComputeCounts <- function(reports, cohorts, params) {
  # Counts the number of times each bit in the Bloom filters was set for
  #     each cohort.
  #
  # Args:
  #   reports: A list of N elements, each containing the
  #       report for a given report
  #   cohorts: A list of N elements, each containing the
  #       cohort number for a given report
  #   params: A list of parameters for the problem
  #
  # Returns:
  #   An mx(k+1) array containing the number of times each bit was set
  #       in each cohort.

  # Check that the cohorts are evenly assigned. We assume that if there
  #     are m cohorts, each cohort should have approximately N/m reports.
  #     The constraint we impose here simply says that cohort bins should
  #     each have within N/m reports of one another. Since the most popular
  #     cohort is expected to have about O(logN/loglogN) reports (which we )
  #     approximate as O(logN) bins for practical values of N, a discrepancy of
  #     O(N) bins seems significant enough to alter expected behavior. This
  #     threshold can be changed to be more sensitive if desired.
  N <- length(reports)
  cohort_freqs <- table(factor(cohorts, levels = 1:params$m))
  imbalance_threshold <- N / params$m
  if ((max(cohort_freqs) - min(cohort_freqs)) > imbalance_threshold) {
    cat("\nNote: You are using unbalanced cohort assignments, which can",
        "significantly degrade estimation quality!\n\n")
  }

  # Count the times each bit was set, and add cohort counts to first column
  counts <- lapply(1:params$m, function(i)
                   Reduce("+", reports[which(cohorts == i)]))
  counts[which(cohort_freqs == 0)] <- data.frame(rep(0, params$k))
  cbind(cohort_freqs, do.call("rbind", counts))
}
