# To test in communication in shell, do:
#
#   mkfifo reqfifo
#   echo '{"command": "init"}' > request-fifo
#
# To test in communication in Python, do:
#   os.mkfifo('blah')
#   f=os.open('blah', os.O_RDWR|os.O_NONBLOCK)
#   os.write(f,'hello\n')
#   os.write(f,'hello\n')
#
# Input commands always come on the request fifo, using a single line per
# request.
#
# TODO:
# - error handling for bad commands

# Request and response lines are JSON.
# NOTE: rjson library has a very strict R 3.1 requirement, so I didn't try it.
library(RJSONIO)  # fromJSON

# For logging
pid <- Sys.getpid()

log <- function(msg) {
  cat(paste(pid, ': ', msg, '\n', sep = ''), file=stderr())
}

.make.dev.error <- function(message) {
  list(dev_error=list(message=message))
}

.write.response <- function(response, f) {
  #s <- tnet.dump(response)
  j = toJSON(response)
  # Must be on a single line!
  # We could also make it length-prefixed, but that introduces unicode issues.
  # This is safe because JSON should not contain actual newlines.  They should
  # all be \ escaped.

  clean = gsub('\n', '', j)
  writeLines(con = f, clean)
  #cat(s, file=f)
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
pgi.loop <- function(handlers) {
  log("Hello from pgi.R (PGI 2 mode)")

  # Each applet is started in its own directory, and we use the standard name
  # 'request-fifo' for the input stream
  req.fifo <- fifo('request-fifo', blocking = TRUE)
  # Open for write, default is nonblocking
  resp.fifo <- fifo('response-fifo', open='w')

  while (1) {
    log("Reading request line")

    # TODO: How does it handle errors?
    req.line <- readLines(req.fifo, n = 1)  # read 1 line

    log("Got request line")

    #pgi.request <- tnet.loadf(req.fifo)

    # This gives a vector
    req.vec = fromJSON(req.line)
    # Turn it into a list, so we can access fields with $
    pgi.request = as.list(req.vec)

    cat(paste("pgi.REQUEST", pgi.request, "\n"))
    log("Got request")

    # on startup
    command <- pgi.request$command
    if (!is.null(command) && command == 'init') {
      pgi.response = list(result='ok')
      .write.response(pgi.response, resp.fifo)
      next()
    }

    log('R1')

    route.name <- pgi.request$route
    if (is.null(route.name)) {
      # error
      pgi.response <- .make.dev.error("No route name in request")
      .write.response(pgi.response, resp.fifo)
      next()
    }

    log('R2')

    request.handler <- handlers[[route.name]]
    if (is.null(request.handler)) {
      pgi.response <- .make.dev.error(
                          paste("No request handler for route", route.name))
      .write.response(pgi.response, resp.fifo)
      next()
    }

    log('R3')

    app.request <- pgi.request$request
    if (is.null(app.request)) {
      pgi.response <- .make.dev.error("Expected 'request' field in PGI request")
      .write.response(pgi.response, resp.fifo)
      next()
    }

    log("Invoking handler")
    pgi.response = .invoke.handler(request.handler, app.request) 

    log("Writing TNET response")
    .write.response(pgi.response, resp.fifo)

    log("Handled request")

    flush(stdout())
  }
}

