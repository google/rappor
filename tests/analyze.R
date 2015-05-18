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

source("analysis/R/analysis_lib.R")
source("analysis/R/read_input.R")
source("analysis/R/decode.R")

source("analysis/R/alternative.R")  # temporary

Log <- function(...) {
  cat('analyze.R: ')
  cat(sprintf(...))
  cat('\n')
}

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


  timing <- system.time({
    # Calls AnalyzeRAPPOR to run the analysis code
    rappor <- AnalyzeRAPPOR(ctx$params, counts, map$map, "FDR", 0.05,
                          date="01/01/01", date_num="100001")
  })

  # The line is searched for, and elapsed time is extracted, by make_summary.py.
  # Should the formating or wording change, make_summary must be updated too.
  Log("Inference took %.3f seconds", timing[["elapsed"]])

  if (is.null(rappor)) {
    stop("RAPPOR analysis failed.")
  }

  Log("Analysis Results:")
  str(rappor)

  rappor
}

LoadActual <- function(prefix_instance) {
  # Load ground truth into context

  h <- paste0(prefix_instance, '_hist.csv')
  read.csv(h)
}

CompareRapporVsActual <- function(ctx) {
  # Prepare input data to be plotted

  actual <- ctx$actual  # from the ground truth file
  rappor <- ctx$rappor  # from output of AnalyzeRAPPOR

  # "s12" -> 12, for graphing
  StringToInt <- function(x) as.integer(substring(x, 2))

  actual_values <- StringToInt(actual$string)
  rappor_values <- StringToInt(rappor$strings)

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
                  dist = rep("rappor", length(rappor_values)))

  # Extend a and r with the values that they are missing.
  if (length(rappor_only) > 0) {
    z <- data.frame(index = rappor_only,
                    proportion = 0.0,
                    dist = "actual")
    a <- rbind(a, z)
  }
  if (length(actual_only) > 0) {
    z <- data.frame(index = actual_only,
                    proportion = 0.0,
                    dist = "rappor")
    r <- rbind(r, z)
  }

  # IMPORTANT: Now a and r have the same rows, but in the wrong order.  Sort by index.
  a <- a[order(a$index), ]
  r <- r[order(r$index), ]

  # L1 distance between actual and rappor distributions
  l1 <- sum(abs(a$proportion - r$proportion))
  # The max L1 distance between two distributions is 2; the max total variation
  # distance is 1.
  total_variation <- l1 / 2

  # Choose false positive strings and their proportion from rappor estimates
  false_pos <- r[r$index %in% rappor_only, c('index', 'proportion')]
  false_neg <- a[a$index %in% actual_only, c('index', 'proportion')]

  Log("False positives:")
  str(false_pos)

  Log("False negatives:")
  str(false_neg)

  metrics <- list(
      num_actual = nrow(actual),  # data frames
      num_rappor = nrow(rappor),
      num_false_pos = nrow(false_pos),
      num_false_neg = nrow(false_neg),
      total_variation = total_variation,
      sum_proportion = sum(rappor$proportion)
      )

  Log("Metrics:")
  str(metrics)

  # Return plot data and metrics
  list(plot_data = rbind(r, a), metrics = metrics)
}

# Colors selected to be friendly to the color blind:
# http://www.cookbook-r.com/Graphs/Colors_%28ggplot2%29/
palette <- c("#E69F00", "#56B4E9")

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
