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
# This library implements the RAPPOR, an anonymous collection mechanism.

library(glmnet)

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

  ests
}

FitLasso <- function(X, Y, intercept = TRUE, cv_step = 1, max_lambda = 100) {
  # Fits a Lasso model to select a subset of columns of X.
  #
  # Input:
  #    X: a design matrix of size km by M (the number of candidate strings).
  #    Y: a vector of size km with estimated counts from EstimateBloomCounts().
  #
  # Output:
  #    lasso: a cross-validated Lasso object.
  #    non_zero: indices of non-zero coefficients for optimal selection of
  #              lambda.

  zero_coefs <- rep(0, ncol(X))
  names(zero_coefs) <- colnames(X)

  lambdas <- seq(0, max_lambda, cv_step)
  mod <- try(cv.glmnet(X, Y, standardize = FALSE, intercept = intercept,
                       lambda = lambdas,
                       type.measure = "mae", nfolds = 10), silent = TRUE)

  # If fitting fails, return an empty data.frame.
  if (class(mod) == "try-error") {
    return(list(fit = NULL, coefs = zero_coefs))
  }

  # More refined lambda's based on the first coarse run.
  if ((as.numeric(ncol(X)) * as.numeric(nrow(X))) < 10^7) {
    min_lambda <- mod$lambda.min
    if (min_lambda == max(lambdas)) {
      lambdas <- seq(301, 500, cv_step)
    } else if (min_lambda == min(lambdas)) {
      lambdas <- seq(0, 1, .01)
    } else {
      lambdas <- c(seq(0, max(0, min_lambda - 2), cv_step),
                   seq(max(0, min_lambda - 2), max(min_lambda + 2, 0), .01),
                   seq(max(0, min_lambda + 2), 500, cv_step))
      lambdas <- sort(unique(lambdas[lambdas > 0]))
    }
    mod <- try(cv.glmnet(X, Y, standardize = FALSE, intercept = intercept,
                         lambda = lambdas,
                         type.measure = "mae", nfolds = 10), silent = TRUE)
    # If fitting fails, return an empty data.frame.
    if (class(mod) == "try-error") {
      return(list(fit = NULL, coefs = zero_coefs))
    }
  }

  # Select the best model based on cross-validation.
  coefs <- coef(mod, s = mod$lambda.min)
  resid <- Y - predict(mod, X, s = mod$lambda.min, type = "response")

  list(fit = mod, coefs = coefs[-1, ], intercept = coefs[1, 1], resid = resid)
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
  mod_var <- summary(mod$fit)$sigma^2
  betas_sd <- rep(sqrt(max(resid_var, mod_var) / (m * h)), length(betas))
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
    coefs <- sort(mod_lasso$coef, decreasing = TRUE)
    non_zero <- sum(coefs > 0)
    if (non_zero > 0) {
      coefs <- names(coefs[1:min(non_zero, k * m * .9)])
    } else {
      coefs <- names(coefs[1:2])
    }
    ind <- match(coefs, names(mod_lasso$coefs))

    # Fit regular linear model to obtain unbiased estimates.
    X <- as.data.frame(apply(as.matrix(map[, coefs]), 2, as.numeric))
    mod <- CustomLM(X, Y)

    # Return complete vector of coefficients with 0's.
    coefs <- rep(0, length(mod_lasso$coefs))
    names(coefs) <- names(mod_lasso$coefs)
    coefs[ind] <- mod$coef
    mod$coefs <- coefs
  } else {
    mod <- CustomLM(as.data.frame(as.matrix(map)), Y)
    lasso <- NULL
  }

  if (correction == "Bonferroni") {
    alpha <- alpha / length(strs)
  }

  inf <- PerformInference(map, Y, N, mod, params, alpha, correction)
  fit <- inf$fit
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
