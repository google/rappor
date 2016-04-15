library(shiny)
source("../../analysis/R/decode.R")
source("../../analysis/R/simulation.R")
source("../../analysis/R/encode.R")

Plot <- function(x, color = "grey") {
  n <- nrow(x)
  if (n < 16) {
    par(mfrow = c(n, 1), mai = c(0, .5, .5, 0))
  } else if (n < 64) {
    par(mfrow = c(n / 2, 2), mai = c(0, .5, .5, 0))
  } else {
    par(mfrow = c(n / 4, 4), mai = c(0, .5, .5, 0))
  }
  for (i in 1:nrow(x)) {
    barplot(x[i, ], main = paste0("Cohort ", i), col = color, border = color)
  }
}

shinyServer(function(input, output) {
  # Example state global variable.
  es <- list()

  # Example buttons states.
  ebs <- rep(0, 3)

  Params <- reactive({
    list(k = as.numeric(input$size),
         h = as.numeric(input$hashes),
         m = as.numeric(input$instances),
         p = as.numeric(input$p),
         q = as.numeric(input$q),
         f = as.numeric(input$f))
  })

  PopParams <- reactive({
    list(as.numeric(input$nstrs),
      as.numeric(input$nonzero),
      input$decay,
      as.numeric(input$expo),
      as.numeric(input$background)
      )
  })

  DecodingParams <- reactive({
    list(as.numeric(input$alpha),
         input$correction)
  })

  Sample <- reactive({
    input$sample
    N <- input$N
    params <- Params()
    pop_params <- PopParams()
    decoding_params <- DecodingParams()
    prop_missing <- input$missing
    fit <- GenerateSamples(N, params, pop_params,
                    alpha = decoding_params[[1]],
                    correction = decoding_params[[2]],
                    prop_missing = prop_missing)
    fit
  })

  # Results summary.
  output$pr <- renderTable({
    Sample()$summary
  },
                           include.rownames = FALSE, include.colnames = FALSE)

  # Results table.
  output$tab <- renderDataTable({
     Sample()$fit
   },
                                options = list(iDisplayLength = 100))

  # Epsilon.
  output$epsilon <- renderTable({
    Sample()$privacy
  },
                                include.rownames = FALSE, include.colnames = FALSE, digits = 4)

  # True distribution.
  output$probs <- renderPlot({
    samp <- Sample()
    probs <- samp$probs
    detected <- match(samp$fit[, 1], samp$strs)
    detection_frequency <- samp$privacy[7, 2]
    PlotPopulation(probs, detected, detection_frequency)
  })

  # True bits patterns.
  output$truth <- renderPlot({
    truth <- Sample()$truth
    Plot(truth[, -1, drop = FALSE], color = "darkblue")
  })

  # Lasso plot.
  output$lasso <- renderPlot({
    fit <- Sample()$lasso
    if (!is.null(fit)) {
      plot(fit)
    }
  })

  output$resid <- renderPlot({
    resid <- Sample()$residual
    params <- Params()
    plot(resid, xlab = "Bloom filter bits", ylab = "Residuals")
    abline(h = c(-1.96, 1.96), lty = 2, col = 2)
    sq <- qnorm(.025 / length(resid))
    abline(h = c(sq, -sq), lty = 2, col = 3, lwd = 2)
    abline(h = c(-3, 3), lty = 2, col = 4, lwd = 2)
    abline(v = params$k * (0:params$m), lty = 2, col = "blue")
    legend("topright", legend = paste0("SD = ", round(sd(resid), 2)), bty = "n")
  })

  # Estimated bits patterns.
  output$ests <- renderPlot({
    ests <- Sample()$ests
    Plot(ests, color = "darkred")
  })

  # Estimated vs truth.
  output$ests_truth <- renderPlot({
    plot(unlist(Sample()$ests), unlist(Sample()$truth[, -1]),
         xlab = "Estimates", ylab = "Truth", pch = 19)
    abline(0, 1, lwd = 4, col = "darkred")
  })

  output$example <- renderPlot({
    params <- Params()
    strs <- Sample()$strs
    map <- Sample()$map
    samp <- Sample()

    # First run on app start.
    value <- sample(strs, 1)
    res <- Encode(value, map, strs, params, N = input$N)

    if (input$new_user > ebs[1]) {
      res <- Encode(es$value, map, strs, params, N = input$N)
      ebs[1] <<- input$new_user
    } else if (input$new_value > ebs[2]) {
      res <- Encode(value, map, strs, params, cohort = es$cohort, id = es$id,
                    N = input$N)
      ebs[2] <<- input$new_value
    } else if (input$new_report > ebs[3]) {
      res <- Encode(es$value, map, strs, params, B = es$B,
                    BP = es$BP, cohort = es$cohort, id = es$id, N = input$N)
      ebs[3] <<- input$new_report
    }
    es <<- res
    ExamplePlot(res, params$k, c(ebs, input$new_user, input$new_value, input$new_report))
  })

})
