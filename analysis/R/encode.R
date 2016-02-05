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

Encode <- function(value, map, strs, params, N, id = NULL,
                   cohort = NULL, B = NULL, BP = NULL) {
  # Encode value to RAPPOR and return a report.
  #
  # Input:
  #    value: value to be encoded
  #    map: a mapping matrix describing where each element of strs map in
  #         each cohort
  #    strs: a vector of possible values with value being one of them
  #    params: a list of RAPPOR parameters described in decode.R
  #    N: sample size
  # Optional parameters:
  #    id: user ID (smaller than N)
  #    cohort: specifies cohort number (smaller than m)
  #    B: input Bloom filter itself, in which case value is ignored
  #    BP: input Permanent Randomized Response (memoized for multiple colections
  #        from the same user

  k <- params$k
  p <- params$p
  q <- params$q
  f <- params$f
  h <- params$h
  m <- params$m
  if (is.null(cohort)) {
    cohort <- sample(1:m, 1)
  }

  if (is.null(id)) {
    id <- sample(N, 1)
  }

  ind <- which(value == strs)

  if (is.null(B)) {
    B <- as.numeric(map[[cohort]][, ind])
  }

  if (is.null(BP)) {
    BP <- sapply(B, function(x) sample(c(0, 1, x), 1,
                                       prob = c(0.5 * f, 0.5 * f, 1 - f)))
  }
  rappor <- sapply(BP, function(x) rbinom(1, 1, ifelse(x == 1, q, p)))

  list(value = value, rappor = rappor, B = B, BP = BP, cohort = cohort, id = id)
}

ExamplePlot <- function(res, k, ebs = 1, title = "", title_cex = 4,
                        voff = .17, acex = 1.5, posa = 2, ymin = 1,
                        horiz = FALSE) {
  PC <- function(k, report) {
    char <- as.character(report)
    if (k > 128) {
      char[char != ""] <- "|"
    }
    char
  }

  # Annotation settings
  anc <- "darkorange2"
  colors <- c("lavenderblush3", "maroon4")

  par(omi = c(0, .55, 0, 0))
  # Setup plotting.
  plot(1:k, rep(1, k), ylim = c(ymin, 4), type = "n",
       xlab = "Bloom filter bits",
       yaxt = "n", ylab = "", xlim = c(0, k), bty = "n", xaxt = "n")
  mtext(paste0("Participant ", res$id, " in cohort ", res$cohort), 3, 2,
        adj = 1, col = anc, cex = acex)
  axis(1, 2^(0:15), 2^(0:15))
  abline(v = which(res$B == 1), lty = 2, col = "grey")

  # First row with the true value.
  text(k / 2, 4, paste0('"', paste0(title, as.character(res$value)), '"'),
       cex = title_cex, col = colors[2], xpd = NA)

  # Second row with BF: B.
  points(1:k, rep(3, k), pch = PC(k, res$B), col = colors[res$B + 1],
         cex = res$B + 1)
  text(k, 3 + voff, paste0(sum(res$B), " signal bits"), cex = acex,
       col = anc, pos = posa)

  # Third row: B'.
  points(1:k, rep(2, k), pch = PC(k, res$BP), col = colors[res$BP + 1],
         cex = res$BP + 1)
  text(k, 2 + voff, paste0(sum(res$BP), " bits on"),
       cex = acex, col = anc, pos = posa)

  # Row 4: actual RAPPOR report.
  report <- res$rappor
  points(1:k, rep(1, k), pch = PC(k, as.character(report)),
         col = colors[report + 1], cex = report + 1)
  text(k, 1 + voff, paste0(sum(res$rappor), " bits on"), cex = acex,
       col = anc, pos = posa)

  mtext(c("True value:", "Bloom filter (B):",
          "Fake Bloom \n filter (B'):", "Report sent\n to server:"),
        2, 1, at = 4:1, las = 2)
  legend("topright", legend = c("0", "1"), fill = colors, bty = "n",
         cex = 1.5, horiz = horiz)
  legend("topleft", legend = ebs, plot = FALSE)
}

PlotPopulation <- function(probs, detected, detection_frequency) {
    cc <- c("gray80", "darkred")
    color <- rep(cc[1], length(probs))
    color[detected] <- cc[2]
    bp <- barplot(probs, col = color, border = color)
    inds <- c(1, c(max(which(probs > 0)), length(probs)))
    axis(1, bp[inds], inds)
    legend("topright", legend = c("Detected", "Not-detected"),
           fill = rev(cc), bty = "n")
    abline(h = detection_frequency, lty = 2, col = "grey")
}
