#!/usr/bin/env Rscript
#
# Use whateve Rscript is in the path.

source('pgi.R')

pid <- Sys.getpid()

echo.handler <- function(state, request) {
  body <- list(state=state, request=request, pid=pid)
  return(list(body_data=body))
}

handlers <-  list(echo=echo.handler)
pgi.loop(handlers)
