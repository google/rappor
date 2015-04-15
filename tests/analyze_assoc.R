#!/usr/bin/Rscript
#
# Copyright 2015 Google Inc. All rights reserved.
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

library("getopt")
setwd("~/git/google_dev_rappor/tests")
source("../analysis/R/encode.R")
source("../analysis/R/decode.R")
source("../analysis/R/simulation.R")
source("../analysis/R/read_input.R")
source("../analysis/R/association.R")

# This function caches the .csv as an .rda for faster loading.  NOTE: It
# assumes the map csv file is immutable. This isn't true if you
# re-run assoc_sim.R. Adjust immutable_flag as required.
# Modified from analysis/R/read_input.R to load 2 or more map files
# into the environment
LoadMapFiles <- function(map_file, map_file2, params = NULL, 
                         immutable_flag = FALSE, quote = "") {
  if (immutable_flag == FALSE) {
    # Read map files without caching them
    cat("Parsing", map_file, "and", map_file2, "...\n")
    map1 <- ReadMapFile(map_file, params = params, quote = quote)
    map2 <- ReadMapFile(map_file2, params = params, quote = quote)
    # association.R requires an rmap component that combines all
    # cohort maps
    # map$map should be split by cohorts
    map1$rmap <- map1$map
    map2$rmap <- map2$map
    split_map <- function(i, map_struct) {
      numbits <- params$k
      indices <- which(as.matrix(
          map_struct[((i - 1) * numbits + 1):(i * numbits),]) == TRUE,
          arr.ind = TRUE)
      sparseMatrix(indices[, "row"], indices[, "col"],
                   dims = c(numbits, max(indices[, "col"])))
    }
    # Apply the split_map function #cohorts (params$m) times
    map1$map <- lapply(1:params$m, function(i) split_map(i, map1$rmap))
    map2$map <- lapply(1:params$m, function(i) split_map(i, map2$rmap))
    map <- list()
    map[[1]] <- map1
    map[[2]] <- map2
    # Load maps to env when not storing it in .rda file
    e <- globalenv()
    e$map <- map
  } else {
    # Reads the map file and creates an R binary .rda.
    # If .rda file already exists, just loads that file.
    
    rda_file1 <- sub(".csv", "", map_file, fixed = TRUE)
    rda_file2 <- sub(".csv", ".rda", map_file2, fixed = TRUE)
    rda_file <- paste(rda_file1, rda_file2, sep = "_")
    
    # file.info() is not implemented yet by the gfile package. One must delete
    # the .rda file manually when the .csv file is updated.
    # csv_updated <- file.info(map_file)$mtime > file.info(rda_file)$mtime
    
    if (!file.exists(rda_file)) {
      cat("Parsing", map_file, "and", map_file2, "...\n")
      map1 <- ReadMapFile(map_file, params = params, quote = quote)
      map2 <- ReadMapFile(map_file2, params = params, quote = quote)
      # association.R requires an rmap component that combines all
      # cohort maps
      # map$map should be split by cohorts
      map1$rmap <- map1$map
      map2$rmap <- map2$map
      split_map <- function(i, map_struct) {
        numbits <- params$k
        indices <- which(as.matrix(
          map_struct[((i - 1) * numbits + 1):(i * numbits),]) == TRUE,
          arr.ind = TRUE)
        sparseMatrix(indices[, "row"], indices[, "col"],
                     dims = c(numbits, max(indices[, "col"])))
      }
      # Apply the split_map function #cohorts (params$m) times
      map1$map <- lapply(1:params$m, function(i) split_map(i, map1$rmap))
      map2$map <- lapply(1:params$m, function(i) split_map(i, map2$rmap))
      map <- list()
      map[[1]] <- map1
      map[[2]] <- map2
      save(map, file = file.path(tempdir(), basename(rda_file)))
      file.copy(file.path(tempdir(), basename(rda_file)), rda_file,
                overwrite = TRUE)
    }
    load(rda_file, .GlobalEnv)
  }
}

# Command line arguments
spec = matrix(c(
  "map1", "m1", 2, "character",
  "map2", "m2", 2, "character",
  "reports", "r", 2, "character",
  "params", "p", 2, "character",
  "help", "h", 0, "logical"
), byrow = TRUE, ncol = 4)
opt = getopt(spec)

# Usage
if (!is.null(opt$help)) {
  cat(getopt(spec, usage = TRUE))
  q(status = 1)
}

# Defaults
if (is.null(opt$map1))    {opt$map1 = "map_1.csv"}
if (is.null(opt$map2))    {opt$map2 = "map_2.csv"}
if (is.null(opt$params))  {opt$params = "params.csv"}
if (is.null(opt$reports)) {opt$reports = "reports.csv"}

params <- ReadParameterFile(opt$params)
LoadMapFiles(opt$map1, opt$map2, params = params,
             immutable_flag = FALSE)
reportsObj <- read.csv(opt$reports, colClasses = c("integer",
                                                   "character",
                                                   "integer",
                                                   "character"),
                       header = FALSE)
# Parsing reportsObj
cohorts <- list()
cohorts[[1]] <- as.list(reportsObj[1])[[1]]
cohorts[[2]] <- as.list(reportsObj[3])[[1]]
reports <- list()
reports[[1]] <- as.list(reportsObj[2])
reports[[2]] <- as.list(reportsObj[4])

# Split strings into bit arrays (as required by assoc analysis)
reports <- lapply(1:2, function(i) {
  # apply the following function to each of reports[[1]] and reports[[2]]
  lapply(reports[[i]][[1]], function(x) {
    # function splits strings and converts them to numeric values  
    as.numeric(strsplit(x, split = "")[[1]])
  })
})

joint_dist <- ComputeDistributionEM(reports, cohorts, map, 
                                    ignore_other = TRUE,
                                    params, marginals = NULL,
                                    estimate_var = FALSE)
print(joint_dist$fit)