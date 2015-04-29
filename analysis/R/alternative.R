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

# alternative.R
#
# This is some messy code to test out alternative regression using pcls().

library(limSolve)
library(Matrix)

# The next two functions create a matrix (G) and a vector (H) encoding
# linear inequality constraints that a solution vector (x) must satisfy:
#                       G * x >= H

# Currently represent two sets of constraints on the solution vector:
#  - all solution coefficients are nonnegative
#  - all solution coefficients don't sum up to more than 1
MakeG <- function(n, X) {
  d <- Diagonal(n)
  last <- rep(-1, n)
  rbind2(rbind2(d, last), -X)
}

MakeH <- function(n, Y, stds) {
  # set the floor at 0.01 to avoid degenerate cases
  YY <- apply(Y + 3 * stds,  # in each bin don't overshoot by more than 3 stds
              1:2,
              function(x) min(1, max(0.01, x)))  # clamp to [0.01,1]

  c(rep(0, n),  # non-negativity condition
    -1,         # coefficients sum up to no more than 1
    -as.vector(t(YY))) # t is important!
}

MakeLseiModel <- function(X, Y, stds) {
  m <- dim(X)[1]
  n <- dim(X)[2]

# no slack variables for now
#   slack <- Matrix(FALSE, nrow = m, ncol = m, sparse = TRUE)
#   colnames(slack) <- 1:m
#   diag(slack) <- TRUE
#
#   G <- MakeG(n + m)
#   H <- MakeH(n + m)
#
#   G[n+m+1,n:(n+m)] <- -0.1
#  A = cbind2(X, slack)

  w <- as.vector(t(1 / stds))
  w_median <- median(w[!is.infinite(w)])
  w[w > w_median] <- w_median * 2
  w <- w / mean(w)

  list(# coerce sparse Boolean matrix X to sparse numeric matrix
       A = Diagonal(x = w) %*% (X + 0),
       B = as.vector(t(Y)) * w,  # transform to vector in the row-first order
       G = MakeG(n, X),
       H = MakeH(n, Y, stds),
       type = 2)  # Since there are no equality constraints, lsei defaults to
                  # solve.QP anyway, but outputs a warning unless type == 2.
}

# CustomLM(X, Y)
ConstrainedLinModel <- function(X,Y) {
  model <- MakeLseiModel(X, Y$estimates, Y$stds)
  coefs <- do.call(lsei, model)$X

#  coefs <- coefs[1:(dim(X)[2])]  # remove slack variables
  names(coefs) <- colnames(X)

  coefs
}

