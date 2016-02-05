library(shiny)

source("../../analysis/R/read_input.R")
source("../../analysis/R/decode.R")

# Random number associated with the session used in exported file names.
seed <- sample(10^6, 1)

PlotCohorts <- function(x, highlighted, color = "grey") {
  n <- nrow(x)
  k <- ncol(x)
  if (n < 16) {
    par(mfrow = c(n, 1), mai = c(0, .5, .5, 0))
  } else if (n < 64) {
    par(mfrow = c(n / 2, 2), mai = c(0, .5, .5, 0))
  } else {
    par(mfrow = c(n / 4, 4), mai = c(0, .5, .5, 0))
  }
  for (i in 1:n) {
    cc <- rep(color, k)
    if (!is.null(highlighted)) {
      ind <- highlighted[which(ceiling(highlighted / k) == i)] %% k
      cc[ind] <- "greenyellow"
    }
    barplot(x[i, ], main = paste0("Cohort ", i), col = cc, border = cc,
            names.arg = "")
  }
}

shinyServer(function(input, output, session) {
  Params <- reactive({
    param_file <- input$params
    if (!is.null(param_file)) {
      params <- ReadParameterFile(param_file$datapath)
      updateSelectInput(session, "size", selected = params$k)
      updateSelectInput(session, "hashes", selected = params$h)
      updateSelectInput(session, "instances", selected = params$m)
      updateSliderInput(session, "p", value = params$p)
      updateSliderInput(session, "q", value = params$q)
      updateSliderInput(session, "f", value = params$f)
    } else {
      params <- list(k = as.numeric(input$size),
                     h = as.numeric(input$hashes),
                     m = as.numeric(input$instances),
                     p = as.numeric(input$p),
                     q = as.numeric(input$q),
                     f = as.numeric(input$f))
    }
    params
  })

  Counts <- reactive({
    params <- Params()
    counts_file <- input$counts
    if (is.null(counts_file)) {
      return(NULL)
    }

    counts <- ReadCountsFile(counts_file$datapath, params)
    updateNumericInput(session, "N", value = sum(counts[, 1]))
    counts
  })

  output$countsUploaded <- reactive({
    ifelse(is.null(input$counts), FALSE, TRUE)
  })
  outputOptions(output, 'countsUploaded', suspendWhenHidden=FALSE)

  Map <- reactive({
    params <- Params()
    map_file <- input$map
    if (is.null(map_file)) {
      return(NULL)
    }

    map <- ReadMapFile(map_file$datapath, params)
    updateSelectInput(session, "selected_string", choices = map$strs, selected = map$strs[1])
    map
  })

  output$mapUploaded <- reactive({
    ifelse(is.null(input$map), FALSE, TRUE)
  })
  outputOptions(output, 'mapUploaded', suspendWhenHidden=FALSE)

  DecodingParams <- reactive({
    list(alpha = as.numeric(input$alpha),
         correction = input$correction)
  })

  Analyze <- reactive({
    if (is.null(input$map) || is.null(input$counts)) {
      return()
    }
    params <- Params()
    map <- Map()
    counts <- Counts()
    decoding_params <- DecodingParams()

    fit <- Decode(counts, map$map, params,
                  alpha = decoding_params$alpha,
                  correction = decoding_params$correction)
    fit
  })

  # Results summary.
  output$pr <- renderTable({
    Analyze()$summary
  },
                           include.rownames = FALSE, include.colnames = FALSE)

  # Results table.
  output$tab <- renderDataTable({
     Analyze()$fit
   },
     options = list(iDisplayLength = 100))

  # Results barplot.
  output$res_barplot <- renderPlot({
    fit <- Analyze()$fit

    par(mai = c(2, 1, 1, .5))

    bp <- barplot(fit$proportion, col = "palegreen",
            main = "Discovered String Distribution")
    abline(h = Analyze()$privacy[7, 2], col = "darkred", lty = 2, lwd = 2)
    text(bp[, 1], 0, paste(fit$strings, " "), srt = 45, adj = c(1, 1), xpd = NA)
    legend("topright", legend = "Detection Frequency", lty = 2, lwd = 2, col = "darkred",
           bty = "n")
  })

  # Epsilon.
  output$epsilon <- renderTable({
    Analyze()$privacy
  },
                                include.rownames = FALSE, include.colnames = FALSE, digits = 4)

  output$map <- renderPlot({
    image(as.matrix(Map()$map), col = c("white", "darkred"), xaxt = "n", yaxt = "n", bty = "n")
  })

  # Estimated bits patterns.
  output$ests <- renderPlot({
    ests <- Analyze()$ests
    ind <- which(input$selected_string == Map()$strs)
    high <- unlist(Map()$map_pos[ind, -1])
    PlotCohorts(ests, high, color = "darkred")
  })

  # Collisions.
  output$collisions <- renderPlot({
    params <- Params()
    map <- Map()
    tab <- table(unlist(map$map_pos[, -1]))
    tab <- tab[as.character(1:(params$k * params$m))]
    tab[is.na(tab)] <- 0
    tab <- matrix(tab, nrow = params$m, byrow = TRUE)

    ind <- which(input$selected_string == map$strs)
    high <- unlist(map$map_pos[ind, -1])

    PlotCohorts(tab, high, color = "navajowhite")
  })

  # Observed counts.
  output$counts <- renderPlot({
    counts <- as.matrix(Analyze()$counts)
    ind <- which(input$selected_string == Map()$strs)
    high <- unlist(Map()$map_pos[ind, -1])
    PlotCohorts(counts, high, color = "darkblue")
  })

  # Downloadable datasets.
  output$download_fit <- downloadHandler(
                                         filename = function() { paste("results_", seed, "_", date(), '.csv', sep='') },
                                         content = function(file) {
                                                     write.csv(Analyze()$fit, file, row.names = FALSE)
                                                   }
                                         )

  output$download_summary <- downloadHandler(
                                         filename = function() { paste("summary_", seed, "_", date(), '.csv', sep='') },
                                         content = function(file) {
                                                     write.csv(rbind(Analyze()$summary, Analyze()$privacy, Analyze()$params),
                                                               file, row.names = FALSE)
                                                   }
                                         )

  output$example_params <- renderTable({
    as.data.frame(ReadParameterFile("params.csv"))
  },
                                include.rownames = FALSE)

  output$example_counts <- renderTable({
    counts <- ReadCountsFile("counts.csv")[, 1:15]
    cbind(counts, rep("...", nrow(counts)))
  },
                                include.rownames = FALSE, include.colnames = FALSE)

  output$example_map <- renderTable({
    map <- ReadMapFile("map.csv", ReadParameterFile("params.csv"))
    map$map_pos[1:10, ]
  },
                                include.rownames = FALSE, include.colnames = FALSE)

})
