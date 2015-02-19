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

HealthHandler <- function(state, request) {
  body <- list(state=state, request=request, pid=pid)
  return(list(body_data=body))
}

# For testing concurrency
SleepHandler <- function(state, request) {
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

ErrorHandler <- function(state, request) {
  oops  # undefined
}

DistHandler <- function(state, request) {
  log('DistHandler')

  str(request$num_reports)

  str(request$sums)  # TODO: change to bit_counts, and flatten

  str(request$candidates_path)

  # TODO: Right now these are at the top level, need to move
  str(request$params)

  # TODO: Look at the files in read_input.R

  # Return value.
  dist = data.frame(x=8, y=9)
  write.csv(dist, 'dist.csv')

  return(list(dist='dist.csv'))
}

# Is there a shortcut for this?
handlers <- list(
    HealthHandler=HealthHandler,
    SleepHandler=SleepHandler,
    DistHandler=DistHandler,
    ErrorHandler=ErrorHandler
    )

pgi.loop(handlers)
