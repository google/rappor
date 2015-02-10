#!/usr/bin/R
#
# Run with R --vanilla --slave -f myScript.R \
#            --args <request in fifo> <response file out dir>
#
# To test in communication in shell, do:
#
#   mkfifo reqfifo
#   echo '@request path:/' > reqfifo
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

# An R package would avoid this.
#source('tnet.R')
#source(file.path(Sys.getenv('PGI_LIB_DIR'), 'tnet.R'))

# For debugging
pid <- Sys.getpid()

log <- function(msg) {
  cat(paste(pid, ': ', msg, '\n', sep = ''), file=stderr())
}

.make.dev.error <- function(message) {
  list(dev_error=list(message=message))
}

.write.response <- function(response, f) {
  s <- tnet.dump(response)
  cat(s, file=f)
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
    # TODO: How does it handle errors?
    pgi.request <- tnet.loadf(req.fifo)
    cat(paste("pgi.REQUEST", pgi.request, "\n"))
    log("Got request")

    # on startup
    command <- pgi.request$command
    if (!is.null(command) && command == 'init') {
      pgi.response = list(result='ok')
      .write.response(pgi.response, resp.fifo)
      next()
    }

    route.name <- pgi.request$route
    if (is.null(route.name)) {
      # error
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


