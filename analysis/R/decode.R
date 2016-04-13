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

# So we don't have to change pwd
source.rappor <- function(rel_path)  {
  abs_path <- paste0(Sys.getenv("RAPPOR_REPO", ""), rel_path)
  source(abs_path)
}

source.rappor('analysis/R/alternative.R')

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
  #    stds: standard deviation of the estimates.

  p <- params$p
  q <- params$q
  f <- params$f
  m <- params$m
  k <- params$k

  stopifnot(m == nrow(obs_counts), k + 1 == ncol(obs_counts))

  p11 <- q * (1 - f/2) + p * f / 2  # probability of a true 1 reported as 1
  p01 <- p * (1 - f/2) + q * f / 2  # probability of a true 0 reported as 1

  p2 <- p11 - p01  # == (1 - f) * (q - p)

  # When m = 1, obs_counts does not have the right dimensions. Fixing this.
  dim(obs_counts) <- c(m, k + 1)

  ests <- apply(obs_counts, 1, function(cohort_row) {
      N <- cohort_row[1]  # sample size for the cohort -- first column is total
      v <- cohort_row[-1] # counts for individual bits
      (v - p01 * N) / p2  # unbiased estimator for individual bits'
                          # true counts. It can be negative or
                          # exceed the total.
    })

  # NOTE: When k == 1, rows of obs_counts have 2 entries.  Then cohort_row[-1]
  # is a singleton vector, and apply() returns a *vector*.  When rows have 3
  # entries, cohort_row[-1] is a vector of length 2 and apply() returns a
  # *matrix*.
  #
  # Fix this by explicitly setting dimensions.  NOTE: It's k x m, not m x k.
  dim(ests) <- c(k, m)

  total <- sum(obs_counts[,1])

  variances <- apply(obs_counts, 1, function(cohort_row) {
      N <- cohort_row[1]
      v <- cohort_row[-1]
      p_hats <- (v - p01 * N) / (N * p2)  # expectation of a true 1
      p_hats <- pmax(0, pmin(1, p_hats))  # clamp to [0,1]
      r <- p_hats * p11 + (1 - p_hats) * p01  # expectation of a reported 1
      N * r * (1 - r) / p2^2  # variance of the binomial
     })

  dim(variances) <- c(k, m)

  # Transform counts from absolute values to fractional, removing bias due to
  #      variability of reporting between cohorts.
  ests <- apply(ests, 1, function(x) x / obs_counts[,1])
  stds <- apply(variances^.5, 1, function(x) x / obs_counts[,1])

  # Some estimates may be set to infinity, e.g. if f=1. We want to account for
  # this possibility, and set the corresponding counts to 0.
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

  fit <- data.frame(string = colnames(X), Estimate = betas,
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
    str_names <- fit$string
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

# Private function
# Decode for Boolean RAPPOR inputs
# Returns a list with attribute fit only. (Inference and other aspects
# currently not incorporated because they're unnecessary for association.)
.DecodeBoolean <- function(counts, params, num_reports) {
  # Boolean variables are reported without cohorts and to estimate counts,
  # first sum up counts across all cohorts and then run EstimateBloomCounts
  # with the number of cohorts set to 1.
  params$m <- 1  # set number of cohorts to 1
  summed_counts <- colSums(counts)  # sum counts across cohorts
  es <- EstimateBloomCounts(params, summed_counts)  # estimate boolean counts

  ests <- es$estimates[[1]]
  std <- es$stds[[1]]

  fit <- data.frame(
           string         = c("TRUE", "FALSE"),
           estimate       = c(ests * num_reports,
                              num_reports - ests * num_reports),
           std_error      = c(std * num_reports, std * num_reports),
           proportion     = c(ests, 1 - ests),
           prop_std_error = c(std, std))

  low_95 <- fit$proportion - 1.96 * fit$prop_std_error
  high_95 <- fit$proportion + 1.96 * fit$prop_std_error

  fit$prop_low_95 <- pmax(low_95, 0.0)
  fit$prop_high_95 <- pmin(high_95, 1.0)
  rownames(fit) <- fit$string

  return(list(fit = fit))
}

CheckDecodeInputs <- function(counts, map, params) {
  # Returns an error message, or NULL if there is no error.

  if (nrow(map) != (params$m * params$k)) {
    return(sprintf(
        "Map matrix has invalid dimensions: m * k = %d, nrow(map) = %d",
        params$m * params$k, nrow(map)))
  }

  if ((ncol(counts) - 1) != params$k) {
    return(sprintf(paste0(
        "Dimensions of counts file do not match: m = %d, k = %d, ",
        "nrow(counts) = %d, ncol(counts) = %d"), params$m, params$k,
        nrow(counts), ncol(counts)))

  }

  # numerically correct comparison
  if (isTRUE(all.equal((1 - params$f) * (params$p - params$q), 0))) {
    return("Information is lost. Cannot decode.")
  }

  return(NULL)  # no error
}

Decode <- function(counts, map, params, alpha = 0.05,
                   correction = c("Bonferroni"), quiet = FALSE, ...) {

  error_msg <- CheckDecodeInputs(counts, map, params)
  if (!is.null(error_msg)) {
    stop(error_msg)
  }

  k <- params$k
  p <- params$p
  q <- params$q
  f <- params$f
  h <- params$h
  m <- params$m

  S <- ncol(map)  # total number of candidates

  N <- sum(counts[, 1])
  if (k == 1) {
    return(.DecodeBoolean(counts, params, N))
  }

  filter_cohorts <- which(counts[, 1] != 0)  # exclude cohorts with zero reports

  # stretch cohorts to bits
  filter_bits <- as.vector(matrix(1:nrow(map), ncol = m)[,filter_cohorts, drop = FALSE])

  map_filtered <- map[filter_bits, , drop = FALSE]

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
                       FitDistribution(e, map_filtered,  quiet))
  }

  coefs_ssd <- N * apply(coefs_all, 2, sd)  # compute sample standard deviations
  coefs_ave <- N * apply(coefs_all, 2, mean)

  # Only select coefficients more than two standard deviations from 0. May
  # inflate empirical SD of the estimates.
  reported <- which(coefs_ave > 1E-6 + 2 * coefs_ssd)

  mod <- list(coefs = coefs_ave[reported], stds = coefs_ssd[reported])

  coefs_ave_zeroed <- coefs_ave
  coefs_ave_zeroed[-reported] <- 0

  residual <- as.vector(t(estimates_stds_filtered$estimates)) -
    map_filtered %*% coefs_ave_zeroed / N

  if (correction == "Bonferroni") {
    alpha <- alpha / S
  }

  inf <- PerformInference(map_filtered[, reported, drop = FALSE],
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
  fit$estimate <- floor(fit$Estimate)
  fit$proportion <- fit$estimate / N

  fit$std_error <- floor(fit$SD)
  fit$prop_std_error <- fit$std_error / N

  # 1.96 standard deviations gives 95% confidence interval.
  low_95 <- fit$proportion - 1.96 * fit$prop_std_error
  high_95 <- fit$proportion + 1.96 * fit$prop_std_error
  # Clamp estimated proportion.  pmin/max: vectorized min and max
  fit$prop_low_95 <- pmax(low_95, 0.0)
  fit$prop_high_95 <- pmin(high_95, 1.0)

  fit <- fit[, c("string", "estimate", "std_error", "proportion",
                 "prop_std_error", "prop_low_95", "prop_high_95")]

  allocated_mass <- sum(fit$proportion)
  num_detected <- nrow(fit)

  ss <- round(inf$SS, digits = 3)
  explained_var <- ss[[1]]
  missing_var <- ss[[2]]
  noise_var <- ss[[3]]

  noise_std_dev <- round(inf$resid_sigma, digits = 3)

  # Compute summary of the fit.
  parameters <-
      c("Candidate strings", "Detected strings",
        "Sample size (N)", "Discovered Prop (out of N)",
        "Explained Variance", "Missing Variance", "Noise Variance",
        "Theoretical Noise Std. Dev.")
  values <- c(S, num_detected, N, allocated_mass,
              explained_var, missing_var, noise_var, noise_std_dev)

  res_summary <- data.frame(parameters = parameters, values = values)

  privacy <- ComputePrivacyGuarantees(params, alpha, N)
  params <- data.frame(parameters =
                       c("k", "h", "m", "p", "q", "f", "N", "alpha"),
                       values = c(k, h, m, p, q, f, N, alpha))

  # This is a list of decode stats in a better format than 'summary'.
  metrics <- list(sample_size = N,
                  allocated_mass = allocated_mass,
                  num_detected = num_detected,
                  explained_var = explained_var,
                  missing_var = missing_var)

  list(fit = fit, summary = res_summary, privacy = privacy, params = params,
       lasso = NULL, residual = as.vector(residual),
       counts = counts[, -1], resid = NULL, metrics = metrics,
       ests = es$estimates  # ests needed by Shiny rappor-sim app      
  )
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
