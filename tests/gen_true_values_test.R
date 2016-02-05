#!/usr/bin/Rscript
#
# gen_reports_test.R

source('analysis/R/util.R')  # Log()

source('tests/gen_true_values.R')  # module under test

library(RUnit)

TestGenerateTrueValues = function() {
  num_clients <- 10
  reports_per_client <- 2
  num_cohorts <- 4
  reports <- GenerateTrueValues('exp', 10, num_clients, reports_per_client,
                                num_cohorts)
  print(reports)

  # 10 clients, 2 reports per client
  checkEquals(20, nrow(reports))

  # 10 unique clients
  checkEquals(10, length(unique(reports$client)))

  # Whether a given client reports different values
  reports_different_values <- rep(FALSE, num_clients)

  for (c in 1:num_clients) {
    my_reports <- reports[reports$client == c, ]
    #Log("CLIENT %d", c)
    #print(my_reports)

    # If every report for this client isn't same, make note of it
    if (length(unique(my_reports$value)) != 1) {
      reports_different_values[[c]] <- TRUE
    }
  }

  # At least one client should report different values.  (Technically this
  # could fail, but is unlikely with 10 clients).
  checkTrue(any(reports_different_values))

  checkEquals(num_cohorts, length(unique(reports$cohort)))
}

TestAll <- function(){
  TestGenerateTrueValues()
}

TestAll()
