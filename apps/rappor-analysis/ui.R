library(shiny)

shinyUI(pageWithSidebar(
                        headerPanel("RAPPOR Analysis"),
                        sidebarPanel(
                                     tabsetPanel(tabPanel("Input",
                                                          fileInput('params', 'Select Params File (optional)',
                                                                    accept=c('txt/csv', 'text/comma-separated-values,text/plain', '.csv')),
                                                          fileInput('counts', 'Select Counts File',
                                                                    accept=c('txt/csv', 'text/comma-separated-values,text/plain', '.csv')),
                                                          fileInput('map', 'Select Map File',
                                                                    accept=c('txt/csv', 'text/comma-separated-values,text/plain', '.csv')),
                                                          br(),
                                                          br()
                                                          ),
                                                 tabPanel("RAPPOR",
                                                          selectInput("size", "Bloom filter size:",
                                                                      c(64, 128, 256, 512, 1024, 2048, 4096),
                                                                      selected = 128),
                                                          selectInput("hashes", "Number of hash functions:",
                                                                      c(1, 2, 4, 8, 16, 32),
                                                                      selected = 2),
                                                          selectInput("instances", "Number of cohorts:",
                                                                      c(1, 2, 4, 8, 16, 32, 64),
                                                                      selected = 8),
                                                          numericInput("N", "Number of reports", 0),
                                                          br(),
                                                          br(),
                                                          br()
                                                          ),
                                                 tabPanel("Privacy",
                                                          sliderInput("p", "Probability of reporting noise (p):",
                                                                      min = .01, max = .99, value = .5, step = .01),
                                                          sliderInput("q", "Probability of reporting signal (q):",
                                                                      min = .01, max = .99, value = .75, step = .01),
                                                          sliderInput("f", "Probability of lies (f):",
                                                                      min = 0, max = .99, value = .5, step = .01),
                                                          br(),
                                                          htmlOutput("epsilon"),
                                                          br(),
                                                          helpText("* In addition to p, q and f, the number of hash functions (set in the RAPPOR tab) also effects privacy guarantees."),
                                                          br(),
                                                          br(),
                                                          br()
                                                          ),
                                                 tabPanel("Decoding",
                                                          sliderInput("alpha", "Alpha - probability of false positive:",
                                                                      min = .01, max = 1, value = .05, step = .01),
                                                          br(),
                                                          selectInput("correction", "Multiple testing correction",
                                                                      c("None", "Bonferroni", "FDR"),
                                                                      selected = "FDR"),
                                                          br(),
                                                          br()
                                                          )
                                     ),
                                     conditionalPanel(
                                                      condition = "output.countsUploaded && output.mapUploaded",
                                                      helpText(actionButton("run", "Run Analysis"), align = "center")
                                                      ),
                                     br(),
                                     br(),
                                     helpText("Version 0.1", align = "center"),
                                     helpText(a("RAPPOR Paper", href="http://arxiv.org/abs/1407.6981"), align = "center")),
                        mainPanel(
                                  conditionalPanel(
                                                   condition = "!output.countsUploaded || !output.mapUploaded",
                                                   helpText(h2("Welcome to the RAPPOR Analysis Tool")),
                                                   helpText("To analyze a RAPPOR collection, please upload three files:"),
                                                   helpText(h3("1. Params file"), "This file specifies the 6 parameters that were used to encode RAPPOR reports. An example is shown below. It must have column names in the header line, 6 columns in this order, and 1 row. "),
                                                   htmlOutput("example_params"),
                                                   helpText(h3("2. Counts file"), "Required.  This file must have as many rows as cohorts. The first column contains the number of reports in the cohort.  The remaining k columns specify the number of times the corresponding bit was set in all reports (in the corresponding cohort). This file cannot have a CSV header line."),
                                                   htmlOutput("example_counts"),
                                                   helpText(h3("3. Map file"), "Required.  The first column contains candidate strings. The remaining columns show which bit each string is hashed to within each cohort. Indices are specified in the extended format, starting with index 1 (not 0!). Because we do not specify a cohort in the map file, indices must be adjusted in the following way. For example, if bits i and j are set in cohort 2, then their corresponding indices are i + k and j + k in the map file. The number of columns is equal to (h * m). This file cannot have a CSV header line."),
                                                   htmlOutput("example_map")
                                                   ),
                                  conditionalPanel(
                                                   condition = "output.countsUploaded && output.mapUploaded",
                                                   tabsetPanel(
                                                               tabPanel("Results",
                                                                        helpText(h3("Summary")), htmlOutput("pr"), br(),
                                                                        downloadButton('download_summary', 'Download Summary'),
                                                                        downloadButton('download_fit', 'Download Results'),
                                                                        br(), br(), dataTableOutput("tab")),
                                                               tabPanel("Distribution", plotOutput("res_barplot", height = "800px")),
                                                               tabPanel("Observed Counts",
                                                                        selectInput("selected_string", "Select String",
                                                                                    ""),
                                                                        plotOutput("counts", height = "800px")),
                                                               tabPanel("Estimated Counts", plotOutput("ests", height = "800px")),
                                                               tabPanel("Collision Counts", plotOutput("collisions", height = "800px")),
                                                               tabPanel("Map", plotOutput("map", height = "800px"))
                                                               )
                                                   )
                                  )
                        ))
