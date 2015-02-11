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

sleep.handler <- function(state, request) {
  body <- list(state=state, request=request, pid=pid)
  return(list(body_data=body))
}

handlers <- list(
    health=health.handler,
    sleep=sleep.handler
    )

pgi.loop(handlers)
