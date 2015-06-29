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

# diagonal matrix with -1
makeAin = function(n) {
  d = diag(x=1, n, n)
  last = rep(-1, n)
  rbind(d, last)
}

makebin = function(n) {
  #ratio = 172318 / 128
  # NOTE: Hard-coded hacks here
  ratio = 70000 / 64
  #ratio = 490000 / 64

  print("RATIO")
  print(ratio)

  c(rep(0, n), -ratio)
}

makeM = function(X,Y) {
  n=dim(X)[2]
  p = makep(n)
  Ain = makeAin(n)
  bin = makebin(n)

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
  M = makeM(X,Y)
  coefs = pcls(M)

  print("SUM(coefs)")
  print(sum(coefs))

  return(coefs)
}

