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

library(Matrix)

source.rappor <- function(rel_path)  {
  abs_path <- paste0(Sys.getenv("RAPPOR_REPO", ""), rel_path)
  source(abs_path)
}

source.rappor("analysis/R/util.R")  # for Log


ReadParameterFile <- function(params_file) {
  # Read parameter file. Format:
  # k, h, m, p, q, f
  # 128, 2, 8, 0.5, 0.75, 0.75

  params <- as.list(read.csv(params_file))
  if (length(params) != 6) {
    stop("There should be exactly 6 columns in the parameter file.")
  }
  if (any(names(params) != c("k", "h", "m", "p", "q", "f"))) {
    stop("Parameter names must be k,h,m,p,q,f.")
  }
  params
}

# Handle the case of redundant cohorts, i.e. the counts file needs to be
# further aggregated to obtain counts for the number of cohorts specified in
# the params file.
#
# NOTE: Why is this happening?
AdjustCounts <- function(counts, params) {
  apply(counts, 2, function(x) {
    tapply(x, rep(1:params$m, nrow(counts) / params$m), sum)
  })
}

ReadCountsFile <- function(counts_file, params, adjust_counts = FALSE) {
  # Read in the counts file.
  if (!file.exists(counts_file)) {
    return(NULL)
  }
  counts <- read.csv(counts_file, header = FALSE)

  if (adjust_counts) {
    counts <- AdjustCounts(counts, params)
  }

  if (nrow(counts) != params$m) {
    stop(sprintf("Got %d rows in the counts file, expected m = %d",
                 nrow(counts), params$m))
  }

  if ((ncol(counts) - 1) != params$k) {
    stop(paste0("Counts file: number of columns should equal to k + 1: ",
                ncol(counts)))
  }

  if (any(counts < 0)) {
    stop("Counts file: all counts must be positive.")
  }

  # Turn counts from a data frame into a matrix.  (In R a data frame and matrix
  # are sometimes interchangeable, but sometimes we need it to be matrix.)
  as.matrix(counts)
}

ReadMapFile <- function(map_file, params) {
  # Read in the map file which is in the following format (two hash functions):
  # str1, h11, h12, h21 + k, h22 + k, h31 + 2k, h32 + 2k ...
  # str2, ...
  # Output:
  #    map: a sparse representation of set bits for each candidate string.
  #    strs: a vector of all candidate strings.

  Log("Parsing %s", map_file)

  map_pos <- read.csv(map_file, header = FALSE, as.is = TRUE)
  strs <- map_pos[, 1]
  strs[strs == ""] <- "Empty"

  # Remove duplicated strings.
  ind <- which(!duplicated(strs))
  strs <- strs[ind]
  map_pos <- map_pos[ind, ]

  n <- ncol(map_pos) - 1
  if (n != (params$h * params$m)) {
    stop(paste0("Map file: number of columns should equal hm + 1:",
                n, "_", params$h * params$m))
  }

  row_pos <- unlist(map_pos[, -1], use.names = FALSE)
  col_pos <- rep(1:nrow(map_pos), times = ncol(map_pos) - 1)

  # TODO: When would this ever happen?
  removed <- which(is.na(row_pos))
  if (length(removed) > 0) {
    Log("Removed %d entries", length(removed))
    row_pos <- row_pos[-removed]
    col_pos <- col_pos[-removed]
  }

  map <- sparseMatrix(row_pos, col_pos,
                      dims = c(params$m * params$k, length(strs)))

  colnames(map) <- strs
  list(map = map, strs = strs, map_pos = map_pos)
}

LoadMapFile <- function(map_file, params) {
  # Reads the map file, caching an .rda (R binary data) version of it to speed
  # up future loads.

  rda_path <- sub(".csv", ".rda", map_file, fixed = TRUE)
  # This must be unique per process, so concurrent processes don't try to
  # write the same file.
  tmp_path <- sprintf("%s.%d", rda_path, Sys.getpid())

  # First save to a temp file, and then atomically rename to the destination.
  if (file.exists(rda_path)) {
    Log("Loading %s", rda_path)
    load(rda_path, .GlobalEnv)  # creates the 'map' variable in the global env
  } else {
    map <- ReadMapFile(map_file, params)

    Log("Saving %s as an rda file for faster access", map_file)
    tryCatch({
      save(map, file = tmp_path)
      file.rename(tmp_path, rda_path)
    }, warning = function(w) {
      Log("WARNING: %s", w)
    }, error = function(e) {
      Log("ERROR: %s", e)
    })
  }
  return(map)
}
