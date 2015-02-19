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
  Log('SleepHandler')

  query <- as.list(request$query)
  n <- query$seconds
  Log('n: %s', n)

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

# Convert request input to a matrix.
MakeCounts <- function(params, num_reports, sums) {
  # convert 1D array to m * k matrix.
  #
  # dim will check the dimensions.  We make our to provide good error messages.

  dim(sums) <- c(params$m, params$k)
  #sums[[, 1]] <- num_reports
  sums

  # cbind combines a matrix and vector like this:
  #
  # cbind( [7 8 9], [ 1 4  ) = [ 7 1 4
  #                   2 5        8 2 5
  #                   3 6 ]      9 3 6 ]
  cbind(num_reports, sums)
}

DistHandler <- function(state, request) {
  Log('DistHandler')

  str(request$num_reports)

  str(request$sums)  # TODO: change to bit_counts, and flatten

  #str(request$candidates_path)

  # TODO: Right now these are at the top level, need to move
  str(request$params)
  params = as.list(request$params)
  str(params)

  # TODO: make this inLook at the files in read_input.R
  counts = MakeCounts(params, request$num_reports, request$sums)

  Log('COUNTS')
  str(counts)
  dim(counts)

  #ReadParameterFile(p)
  #ReadCountsFile(c)
  Log('MAP')
  map <- ReadMapFile(request$candidates_path)$map
  str(map)

  Log('ANALYZE RAPPOR')
  rappor <- AnalyzeRAPPOR(params, counts, map,
                          "FDR", 0.05, 1,
                          date="01/01/01", date_num="100001")
  str(rappor)

  Log('WRITE DATA')

  # Return value.
  dist = data.frame(x=8, y=9)
  write.csv(dist, 'dist.csv')

  return(list(rappor=rappor, dist='dist.csv'))
}

# Is there a shortcut for this?
handlers <- list(
    HealthHandler=HealthHandler,
    SleepHandler=SleepHandler,
    DistHandler=DistHandler,
    ErrorHandler=ErrorHandler
    )

if (!interactive()) {  # allow source('handlers.R')
  pgi.loop(handlers)
}
