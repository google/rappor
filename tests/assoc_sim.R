#!/usr/bin/Rscript

library("getopt")
source("../analysis/R/encode.R")
source("../analysis/R/decode.R")
source("../analysis/R/simulation.R")
source("../analysis/R/association.R")

GetCandidatesFromFile <- function(filename) {
  contents <- read.csv(filename, header = FALSE)
  # Expect 2 rows of candidates
  if(nrow(contents) != 2) {
    stop(paste("Candidate file", filename, "expected to have
               two rows of strings."))
  }
  list(var1 = as.vector(t(contents[1,])),
       var2 = as.vector(t(contents[2,])))
}

# Command line arguments
spec = matrix(c(
  "candidates", "c", 2, "character",    # character for filenames
  "params", "p", 2, "character",
  "reports", "r", 2, "character",
  "help", "h", 0, "logical"
  ), byrow = TRUE, ncol = 4)
opt = getopt(spec)

# Usage
if (!is.null(opt$help)) {
  cat(getopt(spec, usage = TRUE))
  q(status = 1)
}

# Defaults
if (is.null(opt$candidates))  {opt$candidates = "candidates.csv"}
if (is.null(opt$params))      {opt$params = "params.csv"}
if (is.null(opt$reports))     {opt$reports = "reports.csv"}

candidates <- GetCandidatesFromFile(opt$candidates)
print(candidates)