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
# assumes the map csv file is immutable.
# Modified from analysis/R/read_input.R to load 2 or more map files
# into the environment
LoadMapFile <- function(map_file, map_var, params = NULL, quote = "") {
  # Reads the map file and creates an R binary .rda.
  # If .rda file already exists, just loads that file.
  
  rda_file <- sub(".csv", ".rda", map_file, fixed = TRUE)
  
  # file.info() is not implemented yet by the gfile package. One must delete
  # the .rda file manually when the .csv file is updated.
  # csv_updated <- file.info(map_file)$mtime > file.info(rda_file)$mtime
  
  if (!file.exists(rda_file)) {
    cat("Parsing", map_file, "...\n")
    map_var <- ReadMapFile(map_file, params = params, quote = quote)
    save(map_var, file = file.path(tempdir(), basename(rda_file)))
    file.copy(file.path(tempdir(), basename(rda_file)), rda_file,
              overwrite = TRUE)
  }
  load(rda_file, .GlobalEnv)
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
map1 = list()
map2 = list()
LoadMapFile(opt$map1, map1)
LoadMapFile(opt$map2, map2)


