#!/usr/bin/env Rscript
#
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

# Simple tool that wraps the analysis/R library.
#
# To run this you need:
# - ggplot
# - optparse
# - glmnet -- dependency of analysis library

library(optparse)

# For unit tests
is_main <- (length(sys.frames()) == 0)

# Do command line parsing first to catch errors.  Loading libraries in R is
# slow.
if (is_main) {
  option_list <- list(
     make_option(c("-t", "--title"), help="Plot Title")
     )
  parsed <- parse_args(OptionParser(option_list = option_list),
                       positional_arguments = 3)  # input and output
}

library(ggplot2)

# Use CairoPNG if available.  Useful for headless R.
if (library(Cairo, quietly = TRUE, logical.return = TRUE)) {
  png_func = CairoPNG
  cat('Using CairoPNG\n')
} else {
  png_func = png
  cat('Using png\n')
}

source("analysis/R/read_input.R")
source("analysis/R/decode.R")
source("analysis/R/util.R")

LoadContext <- function(prefix_case) {
  # Creates the context, filling it with privacy parameters
  # Arg:
  #    prefix_case: path prefix to the test case, e.g. '_tmp/exp'

  p <- paste0(prefix_case, '_params.csv')

  params <- ReadParameterFile(p)

  ctx <- new.env()

  ctx$params <- params  # so we can write it out later

  ctx
}

RunRappor <- function(prefix_case, prefix_instance, ctx) {
  # Reads counts, map files, runs RAPPOR analysis engine.
  # Args:
  #    prefix_case: path prefix to the test case, e.g., '_tmp/exp'
  #    prefix_instance: path prefix to the test instance, e.g., '_tmp/exp/1'
  #    ctx: context file with params field filled in

  c <- paste0(prefix_instance, '_counts.csv')
  counts <- ReadCountsFile(c)

  m <- paste0(prefix_case, '_map.csv')
  map <- ReadMapFile(m)  # Switch to LoadMapFile if want to cache the result

  # Main decode.R API
  timing <- system.time({
    res <- Decode(counts, map$map, ctx$params)
  })

  # The line is searched for, and elapsed time is extracted, by make_summary.py.
  # Should the formating or wording change, make_summary must be updated too.
  Log("Inference took %.3f seconds", timing[["elapsed"]])

  if (is.null(res)) {
    stop("RAPPOR analysis failed.")
  }

  Log("Decoded results:")
  str(res$fit)

  res$fit
}

LoadActual <- function(prefix_instance) {
  hist_path <- paste0(prefix_instance, '_hist.csv')  # case.csv

  # gen_counts.R (fast_counts mode) outputs this, since we never have true
  # client values.
  if (file.exists(hist_path)) {
    return(read.csv(hist_path))
  }

  # Load ground truth into context
  input_path <- paste0(prefix_instance, '_true_values.csv')  # case.csv
  client_values <- read.csv(input_path)

  # Create a histogram, or R "table".  Column 2 is the true value.
  t <- table(client_values$value)

  d <- as.data.frame(t)  # convert it to a data frame with 'string' and 'count' columns
  colnames(d) <- c('string', 'count')

  d  # return this data frame
}

AlignReports <- function(actual, rappor) {
  # Take the ground truth and RAPPOR output, and aligns them to facilitate
  # further comparison.
  # Args:
  #    actual: the ground truth, a list of (str, count)
  #    rappor: Decode's output
  # Output:
  #    (actual, rappor): two identically sorted structures, of the same length,
  #                      one of the  ground truth, the other of the RAPPOR
  #                      output.

  # "s12" -> 12, for graphing
  StringToInt <- function(x) as.integer(substring(x, 2))

  actual_values <- StringToInt(actual$string)
  rappor_values <- StringToInt(rappor$string)

  # False negatives: AnalyzeRAPPOR failed to find this value (e.g. because it
  # occurs too rarely)
  actual_only <- setdiff(actual_values, rappor_values)

  # False positives: AnalyzeRAPPOR attributed a proportion to a string in the
  # map that wasn't in the true input.
  rappor_only <- setdiff(rappor_values, actual_values)

  total <- sum(actual$count)
  a <- data.frame(index = actual_values,
                  # Calculate the true proportion
                  proportion = actual$count / total,
                  dist = "actual")

  r <- data.frame(index = rappor_values,
                  proportion = rappor$proportion,
                  prop_low_95 = rappor$prop_low_95,
                  prop_high_95 = rappor$prop_high_95,
                  dist = "rappor")

  # Extend a and r with the values that they are missing.
  if (length(rappor_only) > 0) {
    z <- data.frame(index = rappor_only,
                    proportion = 0.0,
                    dist = "false positive")
    a <- rbind(a, z)
  }
  if (length(actual_only) > 0) {
    z <- data.frame(index = actual_only,
                    proportion = 0.0,
                    prop_low_95 = 0,
                    prop_high_95 = 1,
                    dist = "false negative")
    r <- rbind(r, z)
  }

  rownames(a) <- a$index
  rownames(r) <- r$index

  # IMPORTANT: Now a and r have the same rows, but in the wrong order. Sort by index.
  list(actual = a[order(a$index), ], rappor = r[order(r$index), ])
}

CompareRapporVsActual <- function(ctx) {
  # Prepare input data to be plotted

  aligned <- AlignReports(ctx$actual, ctx$rappor)

  actual <- aligned$actual
  rappor <- aligned$rappor

  # L1 distance between actual and rappor distributions
  l1 <- sum(abs(actual$proportion - rappor$proportion))
  # The max L1 distance between two distributions is 2; the max total variation
  # distance is 1.
  total_variation <- l1 / 2

  num_95CI <- sum(rappor$dist == "rappor"
                  & (actual$proportion > rappor$prop_low_95)
                  & (actual$proportion < rappor$prop_high_95))

  # Choose false positive strings and their proportion from rappor estimates
  false_pos <- which(actual$dist == "false positive")
  false_neg <- which(rappor$dist == "false negative")

  Log("False positives:")
  str(rappor[false_pos, c('index', 'proportion')])

  Log("False negatives:")
  str(actual[false_neg, c('index', 'proportion')])

  # NOTE: We should call Decode() directly, and then num_rappor is
  # metrics$num_detected, and sum_proportion is metrics$allocated_mass.
  metrics <- list(
      num_actual = nrow(ctx$actual),  # data frames
      num_rappor = nrow(ctx$rappor),
      num_false_pos = length(false_pos),
      num_false_neg = length(false_neg),
      total_variation = total_variation,
      num_95CI = num_95CI,
      sum_proportion = sum(rappor$proportion)
      )

  Log("Metrics:")
  str(metrics)

  levels(rappor$dist) <- c(levels(rappor$dist), "false positive")
  levels(actual$dist) <- c(levels(actual$dist), "false negative")

  rappor[false_pos,]$dist <- "false positive"
  actual[false_neg,]$dist <- "false negative"

  plot_data <- rbind(rappor[-false_neg, c('index', 'proportion', 'dist')],
                     actual[-false_pos,])

  # Return plot data and metrics
  list(plot_data = plot_data, metrics = metrics)
}

# Colors selected to be friendly to the color blind:
# http://www.cookbook-r.com/Graphs/Colors_%28ggplot2%29/
palette <- c("#009E73",  # lime green
             "#E69F00",  # orange
             "#56B4E9",  # light blue
             "#0072B2"   # dark blue
             )

PlotAll <- function(d, title) {
  # NOTE: geom_bar makes a histogram by default; need stat = "identity"
  g <- ggplot(d, aes(x = index, y = proportion, fill = factor(dist)))
  b <- geom_bar(stat = "identity", width = 0.7,
                position = position_dodge(width = 0.8))
  t <- ggtitle(title)
  g + b + t + scale_fill_manual(values=palette)
}

WritePlot <- function(p, outdir, width = 800, height = 600) {
  filename <- file.path(outdir, 'dist.png')
  png_func(filename, width=width, height=height)
  plot(p)
  dev.off()
  Log('Wrote %s', filename)
}

WriteSummary <- function(metrics, outdir) {
  filename <- file.path(outdir, 'metrics.csv')
  write.csv(metrics, file = filename, row.names = FALSE)
  Log('Wrote %s', filename)
}

main <- function(parsed) {
  args <- parsed$args
  options <- parsed$options

  input_case_prefix <- args[[1]]
  input_instance_prefix <- args[[2]]
  output_dir <- args[[3]]

  # increase ggplot font size globally
  theme_set(theme_grey(base_size = 16))

  # NOTE: It takes more than 2000+ ms to get here, while the analysis only
  # takes 500 ms or so (as measured by system.time).

  ctx <- LoadContext(input_case_prefix)
  ctx$rappor <- RunRappor(input_case_prefix, input_instance_prefix, ctx)
  ctx$actual <- LoadActual(input_instance_prefix)

  d <- CompareRapporVsActual(ctx)
  p <- PlotAll(d$plot_data, options$title)

  WriteSummary(d$metrics, output_dir)
  WritePlot(p, output_dir)
}

if (is_main) {
  main(parsed)
}
