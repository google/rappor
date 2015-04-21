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

# The next two functions create a matrix (G) and a vector (H) encoding
# linear inequality constraints that a solution vector (x) must satisfy:
#                       G * x >= H

# Currently represent two sets of constraints on the solution vector:
#  - all solution coefficients are nonnegative
#  - all solution coefficients don't sum up to more than 1
MakeG <- function(n) {
  d <- diag(x=1, n, n)
  last <- rep(-1, n)
  rbind(d, last)
}

MakeH <- function(n) {
  c(rep(0, n), -1)
}

MakeLseiModel <- function(X, Y) {
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

  list(A = X,
       B = Y,
       G = MakeG(n),
       H = MakeH(n) )
}

# CustomLM(X, Y)
ConstrainedLinModel <- function(X,Y) {
  model <- MakeLseiModel(X, Y)
  coefs <- do.call(lsei, model)$X

#  coefs <- coefs[1:(dim(X)[2])]  # remove slack variables
  names(coefs) <- colnames(X)

  coefs
}

