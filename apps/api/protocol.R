# To test in communication in shell, do:
#
#   mkfifo reqfifo
#   echo '{"command": "init"}' > request-fifo
#
# To test in communication in Python, do:
#   os.mkfifo('request-fifo')
#   f = os.open('request-fifo', os.O_RDWR|os.O_NONBLOCK)
#   os.write(f, '{"command": "init"}\n')
#   os.write(f, '{"command": "init"}\n')
#
# Input commands are read as a single JSON line on the request fifo.
# Responses are written as single JSON line on the response fifo.

# The rjson library has a very strict R 3.1 requirement, so I didn't try it.

library(RJSONIO)  # fromJSON, toJSON

# For logging
pid <- Sys.getpid()

# NOTE: Has to be capital 'Log' to avoid clobbering math log()!
Log <- function(fmt, ...) {
  msg <- sprintf(fmt, ...)
  cat(paste('PID ', pid, ': ', msg, '\n', sep = ''), file=stderr())
}

.make.dev.error <- function(message, error = NULL) {
  list(dev_error = list(message = message, error = error))
}

.write.response <- function(response, f) {
  t <- system.time( j <- toJSON(response) )
  Log('toJSON took %f seconds, got %d chars', t[['elapsed']], nchar(j))

  # Must be on a single line!
  # We could also make it length-prefixed, but that introduces unicode issues.
  # This is safe because JSON should not contain actual newlines.  They should
  # all be \ escaped.
  clean <- gsub('\n', '', j)

  writeLines(con = f, clean)
}

# Invoke a request handler, catching exceptions.
.invoke.handler <- function(request.handler, app.request) {
  state <- list()
  app.response <- request.handler(state, app.request)
  pgi.response <- list(response=app.response)
  return(pgi.response)
}

# Run the request loop.
#
# Args:
#   handlers: list of name -> handler
HandleRequests <- function(handlers) {
  Log("Hello from pgi.R (PGI 2 mode)")

  # Each applet is started in its own directory, and we use the standard name
  # 'request-fifo' for the input stream
  req.fifo <- fifo('request-fifo', blocking = TRUE)
  # Open for write, default is nonblocking
  resp.fifo <- fifo('response-fifo', open='w')

  while (1) {
    Log('------------------------')
    Log('Waiting for request line')

    # TODO: How does it handle errors?
    req.line <- readLines(req.fifo, n = 1)  # read 1 line

    Log('Got request line')

    # This gives a vector
    t <- system.time( req.vec <- fromJSON(req.line) )
    Log('fromJSON took %f seconds, %d chars', t[['elapsed']], nchar(req.line))

    # Turn it into a list, so we can access fields with $
    pgi.request <- as.list(req.vec)

    # on startup
    command <- pgi.request$command
    if (!is.null(command) && command == 'init') {
      pgi.response <- list(result='ok')
      .write.response(pgi.response, resp.fifo)
      next()
    }

    route.name <- pgi.request$route
    if (is.null(route.name)) {
      pgi.response <- .make.dev.error("No route name in request")
      .write.response(pgi.response, resp.fifo)
      next()
    }

    request.handler <- handlers[[route.name]]
    if (is.null(request.handler)) {
      pgi.response <- .make.dev.error(
                          paste("No request handler for route", route.name))
      .write.response(pgi.response, resp.fifo)
      next()
    }

    Log('pgi.request: ')
    str(pgi.request)  # prints to stdout

    app.request <- pgi.request$request

    if (is.null(app.request)) {
      pgi.response <- .make.dev.error("Missing 'request' field")
      .write.response(pgi.response, resp.fifo)
      next()
    }

    Log("Invoking handler")

    # Invoking it like this can show a better traceback than tryCatch
    #pgi.response <- .invoke.handler(request.handler, app.request)

    result <- tryCatch(.invoke.handler(request.handler, app.request),
                       error = function(e) e)
    if (inherits(result, 'error')) {
      fmt <- 'ERROR invoking handler for route %s.  (See server --log-dir)'
      msg <- sprintf(fmt, route.name)
      Log(msg)
      str(result)
      pgi.response <- .make.dev.error(msg, error = result)
      # traceback() doesn't work here, because we caught the error :(
    } else {
      pgi.response <- result
    }

    Log("Writing JSON response")
    .write.response(pgi.response, resp.fifo)

    flush(stdout())
  }
}
