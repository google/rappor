#!/usr/bin/env Rscript
#
# Use Rscript in PATH so we can use a locally compiled R.

src <- Sys.getenv('RAPPOR_SRC')  # required
source(file.path(src, 'apps/api/protocol.R'))

source(file.path(src, 'analysis/R/decode.R'))
#source(file.path(src, 'analysis/R/encode.R'))
source(file.path(src, 'analysis/R/analysis_lib.R'))
source(file.path(src, 'analysis/R/read_input.R'))

pid <- Sys.getpid()

health.handler <- function(state, request) {
  body <- list(state=state, request=request, pid=pid)
  return(list(body_data=body))
}

# For testing concurrency
sleep.handler <- function(state, request) {
  log('SleepHandler')

  query <- as.list(request$query)
  n <- query$seconds
  log('n: %s', n)

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

dist.handler <- function(state, request) {
  log('DistHandler')

  # TODO: Read request$csv

  body <- list(msg='dist', request=request, pid=pid)
  counts = ReadCountsFile('foo.csv')

  params = read.csv('params.csv')

  # Return value.
  dist = data.frame(x=8, y=9)
  write.csv(dist, 'dist.csv')

  return(list(body_data=body, counts=counts, params=params, dist='dist.csv'))
}

handlers <- list(
    health=health.handler,
    sleep=sleep.handler,
    dist=dist.handler
    )

pgi.loop(handlers)
