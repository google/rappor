#!/usr/bin/env Rscript
#
# Use whatever Rscript is in the path.

# TODO: Use realpath
source('../pgi.R')

pid <- Sys.getpid()

health.handler <- function(state, request) {
  body <- list(state=state, request=request, pid=pid)
  return(list(body_data=body))
}

# For testing concurrency
sleep.handler <- function(state, request) {
  n <- request$sleepSeconds
  if (!is.null(n)) {
    n = as.numeric(n)
    n = min(n, 5)  # don't let someone tie up this process for too long

    Sys.sleep(n)
    msg <- sprintf('Slept %d seconds', n)
  } else {
    msg <- "Didn't sleep"
  }
  body <- list(msg=msg, request=request, pid=pid)
  return(list(body_data=body))
}

handlers <- list(
    health=health.handler,
    sleep=sleep.handler
    )

pgi.loop(handlers)
