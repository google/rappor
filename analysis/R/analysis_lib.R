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


GetFN <- function(name) {
  # Helper function to strip extension from the filename.
  strsplit(basename(name), ".", fixed = TRUE)[[1]][1]
}

ValidateInput <- function(params, counts, map) {
  val <- "valid"
  if (is.null(counts)) {
    val <- "No counts file found. Skipping"
    return(val)
  }

  if (nrow(map) != (params$m * params$k)) {
    val <- paste("Map does not match the counts file!",
                 "mk = ", params$m * params$k,
                 "nrow(map):", nrow(map),
                 collapse = " ")
  }

  if ((ncol(counts) - 1) != params$k) {
    val <- paste("Dimensions of counts file do not match:",
                 "m =", params$m, "counts rows: ", nrow(counts),
                 "k =", params$k, "counts cols: ", ncol(counts) - 1,
                 collapse = " ")
  }

  # numerically correct comparison
  if(isTRUE(all.equal((1 - params$f) * (params$p - params$q), 0)))
    stop("Information is lost. Cannot decode.")

  val
}

AnalyzeRAPPOR <- function(params, counts, map, correction, alpha,
                          experiment_name = "", map_name = "", config_name = "",
                          date = NULL, date_num = NULL, ...) {
  val <- ValidateInput(params, counts, map)
  if (val != "valid") {
    cat(val, "\n")
    return(NULL)
  }

  cat("Sample Size: ", sum(counts[, 1]), "\n",
      "Number of cohorts: ", nrow(counts), "\n", sep = "")

  fit <- Decode(counts, map, params, correction = correction,
                alpha = alpha, ...)

  res <- fit$fit

  if (nrow(fit$fit) > 0) {
    res$rank <- 1:nrow(fit$fit)
    res$detected <- fit$summary[2, 2]
    res$sample_size <- fit$summary[3, 2]
    res$detected_prop <- fit$summary[4, 2]
    res$explained_var <- fit$summary[5, 2]
    res$missing_var <- fit$summary[6, 2]

    res$exp_e_1 <- fit$privacy[3, 2]
    res$exp_e_inf <- fit$privacy[5, 2]
    res$detection_freq <- fit$privacy[7, 2]
    res$correction <- correction
    res$alpha <- alpha

    res$experiment <- experiment_name
    res$map <- map_name
    res$config <- config_name
    res$date <- date
    res$date_num <- date_num
  }
  else
    print("INSUFFICIENT DATA FOR MEANINGFUL ANSWER.")

  res
}
