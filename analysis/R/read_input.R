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
# Read parameter, counts and map files.

gfile <- function(str) { str }  # NOTE: gfile will be identity function in open source version
library(Matrix)

ReadParameterFile <- function(params_file) {
  # Read parameter file. Format:
  # k, h, m, p, q, f
  # 128, 2, 8, 0.5, 0.75, 0.75

  params <- as.list(read.csv(gfile(params_file)))
  if (length(params) != 6) {
    stop("There should be exactly 6 columns in the parameter file.")
  }
  if (any(names(params) != c("k", "h", "m", "p", "q", "f"))) {
    stop("Parameter names must be k,h,m,p,q,f.")
  }
  params
}

ReadCountsFile <- function(counts_file, params = NULL) {
  # Read in the counts file.
  if (!file.exists(counts_file)) {
    return(NULL)
  }
  counts <- read.csv(gfile(counts_file), header = FALSE)

  if (!is.null(params)) {
    if (nrow(counts) != params$m) {
      stop("Counts file: number of rows should equal number of cohorts (m).")
    }

    if ((ncol(counts) - 1) != params$k) {
      stop(paste0("Counts file: number of columns should equal to k + 1: ",
                  ncol(counts)))
    }
  }

  if (any(counts < 0)) {
    stop("Counts file: all counts must be positive.")
  }

  counts
}

ReadMapFile <- function(map_file, params = NULL, quote = "") {
  # Read in the map file which is in the following format (two hash functions):
  # str1, h11, h12, h21 + k, h22 + k, h31 + 2k, h32 + 2k ...
  # str2, ...
  # Output:
  #    map: a sparse representation of set bits for each candidate string.
  #    strs: a vector of all candidate strings.

  map_pos <- read.csv(gfile(map_file), header = FALSE, as.is = TRUE,
                      quote = quote)
  strs <- map_pos[, 1]
  strs[strs == ""] <- "Empty"

  # Remove duplicated strings.
  ind <- which(!duplicated(strs))
  strs <- strs[ind]
  map_pos <- map_pos[ind, ]

  if (!is.null(params)) {
    n <- ncol(map_pos) - 1
    if (n != (params$h * params$m)) {
      stop(paste0("Map file: number of columns should equal hm + 1:",
                  n, "_", params$h * params$m))
    }
  }
  row_pos <- unlist(map_pos[, -1], use.names = FALSE)
  col_pos <- rep(1:nrow(map_pos), times = ncol(map_pos) - 1)
  removed <- which(is.na(row_pos))
  if (length(removed) > 0) {
    row_pos <- row_pos[-removed]
    col_pos <- col_pos[-removed]
  }

  if (!is.null(params)) {
    map <- sparseMatrix(row_pos, col_pos,
                        dims = c(params$m * params$k, length(strs)))
  } else {
    map <- sparseMatrix(row_pos, col_pos)
  }
  colnames(map) <- strs
  list(map = map, strs = strs, map_pos = map_pos)
}

LoadMapFile <- function(map_file, params = NULL, quote = "") {
  # Reads the map file and creates an R binary .rda. If the .rda file already
  # exists, just loads that file. NOTE: It assumes the map file is
  # immutable.

  rda_file <- sub(".csv", ".rda", map_file, fixed = TRUE)

  # file.info() is not implemented yet by the gfile package. One must delete
  # the .rda file manually when the .csv file is updated.
  # csv_updated <- file.info(map_file)$mtime > file.info(rda_file)$mtime

  if (!file.exists(rda_file)) {
    cat("Parsing", map_file, "...\n")
    map <- ReadMapFile(map_file, params = params, quote = quote)
    cat("Saving", map_file, "as an rda file for faster access.\n")
    save(map, file = file.path(tempdir(), basename(rda_file)))
    file.copy(file.path(tempdir(), basename(rda_file)), rda_file,
              overwrite = TRUE)
  }
  load(gfile(rda_file), .GlobalEnv)
  return(map)
}
