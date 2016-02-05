#!/usr/bin/Rscript
#
# gen_reports_test.R

source('analysis/R/util.R')  # Log()

source('tests/gen_true_values_assoc.R')  # module under test

library(RUnit)

TestGenerateTrueValuesAssoc <- function() {
  # list for support of var1, var2, 
  # total number of reports
  # num_cohorts
  res <- GenerateTrueValuesAssoc(list(20, 5), 1000, 32)
  # print(res$values)

  # 1000 reports
  checkEquals(1000, length(res$values[[1]]))

  # support(var1) <= 20
  # support(var2) <= 5
  checkTrue(max(res$values[[1]]) <= 20)
  checkTrue(max(res$values[[2]]) <= 5)

  # Ensure cohorts are filled up
  checkEquals(32, length(unique(res$cohort)))

  # TODO: Add tests to confirm (w.h.p.?) that certain distribution aspects are
  # as expected (such as the zipfian on marginals)
}

TestAll <- function(){
  TestGenerateTrueValuesAssoc()
}

TestAll()
