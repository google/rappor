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

#
# Run unit tests for RAPPOR R code.

library(RUnit)

run_tests <- function() {
  dirs <- "analysis/test"  # Run from root
  test_suite <- defineTestSuite("rappor", dirs, testFileRegexp = "_test.R$",
                                testFuncRegexp = "^Test")
  stopifnot(isValidTestSuite(test_suite))

  test_result <- runTestSuite(test_suite)

  printTextProtocol(test_result)  # print to stdout

  result <- test_result[[1]]  # Result for our only suite

  # Sanity check: fail if there were no tests found.
  if (result$nTestFunc == 0) {
    cat("No tests found.\n")
    return(FALSE)
  }
  if (result$nFail != 0 || result$nErr != 0) {
    cat("Some tests failed.\n")
    return(FALSE)
  }
  return(TRUE)
}

if (!run_tests()) {
  quit(status = 1)
}
