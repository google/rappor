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

library(mgcv)


# uniform vector
makep = function(n) {
  rep(1, n) / (n+1)
}

# The next two functions create a matrix (Ain) and a vector (bin) encoding
# linear inequality constraints that a solution vector (x) must satisfy: 
#                       Ain * x > bin

# Currently represent two sets of constraints on the solution vector: 
#  - all solution coefficients are nonnegative
#  - all solution coefficients don't sum up to more than 1
makeAin = function(n) {
  d = diag(x=1, n, n)
  last = rep(-1, n)
  rbind(d, last)
}

makebin = function(n) {
  c(rep(0, n), -1)
}

makeM = function(X,Y) {
  n=dim(X)[2]
  p = makep(n)
  Ain = makeAin(n)
  bin = makebin(n)
  
  # Encodes the model with the following properties:
  #   X - the design matrix
  #   Ain, bin - linear inequality constraints on feasible solution
  #   p - initial parameter estimates, must be feasible, i.e., satisfy all 
  #       constraints
  list(X=as.matrix(X),
       p=p,
       off=array(0,0),
       S=list(),
       Ain=Ain,
       bin=bin,
       C=matrix(0,0,0),
       sp=array(0,0),
       y=Y,
       w=rep(1, length(Y)) )
}

# CustomLM(X, Y)
newLM = function(X,Y) {
  M <- makeM(X,Y)
  coefs <- pcls(M)
  names(coefs) <- colnames(X) 

  print("SUM(coefs)")
  print(sum(coefs))

  coefs
}

