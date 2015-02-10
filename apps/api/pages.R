#!/usr/bin/R --vanilla --slave -f

source(file.path(Sys.getenv('PGI_LIB_DIR'), 'pgi.R'))

pid <- Sys.getpid()

echo.handler <- function(state, request) {
  body <- list(state=state, request=request, pid=pid)
  return(list(body_data=body))
}

handlers <-  list(echo=echo.handler)
pgi.loop(handlers)
