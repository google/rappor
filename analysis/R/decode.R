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

# Test.  Change this to use pcls in alternative.R.
#USE_PCLS <- TRUE
USE_PCLS <- FALSE

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
  #    ests: a matrix of size m by x with estimated counts for the number of
  #          times each bit was set in the true Bloom filter.

  p <- params$p
  q <- params$q
  f <- params$f

  # N = x[1] is the sample size for cohort i.
  ests <- t(apply(obs_counts, 1, function(x) {
    (x[-1] - (p + .5 * f * q - .5 * f * p) * x[1]) / ((1 - f) * (q - p))
  }))

  # Some estimates may be set to infinity, e.g. if f=1. We want to
  #     account for this possibility, and set the corresponding counts
  #     to 0.
  ests[abs(ests) == Inf] <- 0
  ests
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
  #    lasso: a cross-validated Lasso object.
  #    coefs: a vector of size ncol(X) of coefficients.
  #    intercept: estimate of the intercept.
  #    resid: residuals estimates.

  zero_coefs <- rep(0, ncol(X))
  names(zero_coefs) <- colnames(X)

  mod <- try(glmnet(X, Y, standardize = FALSE, intercept = intercept,
                    pmax = ceiling(length(Y) * .9)),
             silent = TRUE)

  # If fitting fails, return an empty data.frame.
  if (class(mod)[1] == "try-error") {
    return(list(fit = NULL, coefs = zero_coefs, intercept = 0, resid = NULL))
  } else {
    coefs <- coef(mod)
    intercept <- coefs[1, ncol(coefs)]
    coefs <- coefs[-1, ncol(coefs)]
    predicted <- predict(mod, X, type = "response")
    resid <- Y - predicted[, ncol(predicted)]
    list(fit = mod, coefs = coefs, intercept = intercept, resid = resid)
  }
}

CustomLM <- function(X, Y) {
  if (class(X) == "ngCMatrix") {
    X <- as.data.frame(apply(as.matrix(X), 2, as.numeric))
  }
  mod <- lm(Y ~ ., data = X)
  resid <- Y - predict(mod, X)
  list(fit = mod, coefs = coef(mod)[-1], intercept = coef(mod)[1],
       resid = resid)
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
  if (!USE_PCLS) {
    mod_var <- summary(mod$fit)$sigma^2
    betas_sd <- rep(sqrt(max(resid_var, mod_var) / (m * h)), length(betas))
  } else {
    mod_var <- 0
    betas_sd <- 1
  }
  z_values <- betas / betas_sd

  # 1-sided t-test.
  p_values <- pnorm(z_values, lower = FALSE)

  fit <- data.frame(String = colnames(X), Estimate = betas,
                    SD = betas_sd, z_stat = z_values, pvalue = p_values,
                    stringsAsFactors = FALSE)

  if (correction == "FDR") {
    fit <- fit[order(fit$pvalue, decreasing = FALSE), ]
    ind <- which(fit$pvalue < (1:nrow(fit)) * alpha / nrow(fit))
    if (length(ind) > 0) {
      fit <- fit[1:max(ind), ]
    } else {
      fit <- fit[numeric(0), ]
    }
  } else {
    fit <- fit[fit$p < alpha, ]
  }

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

Decode <- function(counts, map, params, alpha = 0.05,
                   correction = c("Bonferroni"), ...) {
  # In basic RAPPOR, the corrected counts are exactly the estimates of
  #     true variable counts.

  k <- params$k
  p <- params$p
  q <- params$q
  f <- params$f
  h <- params$h
  m <- params$m

  strs <- colnames(map)
  ests <- EstimateBloomCounts(params, counts)
  N <- sum(counts[, 1])
  Y <- as.vector(t(ests))

  if (ncol(map) > (k * m * .8) ||
      (as.numeric(ncol(map)) * as.numeric(nrow(map))) > 10^6) {
    mod_lasso <- FitLasso(map, Y, ...)
    lasso <- mod_lasso$fit

    # Select non-zero coefficients.
    non_zero <- which(mod_lasso$coefs > 0)
    if (length(non_zero) == 0) {
      non_zero <- 1:2
    }

    # Fit regular linear model to obtain unbiased estimates.
    X <- as.data.frame(apply(as.matrix(map[, non_zero]), 2, as.numeric))

    if (!USE_PCLS) {

      mod <- CustomLM(X, Y)

      # Return complete vector of coefficients with 0's.
      coefs <- rep(0, length(mod_lasso$coefs))
      names(coefs) <- names(mod_lasso$coefs)
      coefs[non_zero] <- mod$coef
      coefs[is.na(coefs)] <- 0
      mod$coefs <- coefs

    } else {
      print("CALLING newLM")

      constrained_coefs <- newLM(X, Y)

      # new coefs vector with same names and length as lasso coefs
      coefs <- rep(0, length(mod_lasso$coefs))
      names(coefs) <- names(mod_lasso$coefs)

      mod = list()
      coefs[non_zero] <- constrained_coefs
      mod$coefs <- coefs
    }
  } else {
    print('Decode: CustomLM')
    mod <- CustomLM(as.data.frame(as.matrix(map)), Y)
    lasso <- NULL
  }

  if (correction == "Bonferroni") {
    alpha <- alpha / length(strs)
  }

  inf <- PerformInference(map, Y, N, mod, params, alpha, correction)
  fit <- inf$fit
  # If this is a basic RAPPOR instance, just use the counts for the estimate
  #     (Check if the map is diagonal to tell if this is basic RAPPOR.)
  if (sum(map) == sum(diag(map))) {
    fit$Estimate <- colSums(counts)[-1]
  }
  resid <- mod$resid / inf$resid_sigma

  # Estimates from the model are per instance so must be multipled by h.
  # Standard errors are also adjusted.
  fit$Total_Est <- floor(fit$Estimate * m)
  fit$Total_SD <- floor(fit$SD * m)
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
  values <- c(length(strs), nrow(fit), N, round(sum(fit[, 2]) / N, 3),
              round(inf$SS, 3),
              round(inf$resid_sigma, 3))
  res_summary <- data.frame(parameters = parameters, values = values)

  privacy <- ComputePrivacyGuarantees(params, alpha, N)
  params <- data.frame(parameters =
                       c("k", "h", "m", "p", "q", "f", "N", "alpha"),
                       values = c(k, h, m, p, q, f, N, alpha))

  list(fit = fit, summary = res_summary, privacy = privacy, params = params,
       lasso = lasso, ests = ests, counts = counts[, -1], resid = resid)
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
