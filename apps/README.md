RAPPOR Shiny Apps
=================

This directory contains web apps written using the [Shiny][shiny] web framework
from [RStudio][rstudio].

To run them, first install Shiny:

    $ R
    ...
    > install.packages('shiny')
    ...

(You can view Shiny's platform requirements in
[CRAN](http://cran.r-project.org/web/packages/shiny/index.html).)

Then change to the app directory, and execute the `run_app.sh` script:

    $ cd rappor/apps/rappor-analysis
    $ ./run_app.sh
    ...
    Listening on http://0.0.0.0.:6789

Visit http://localhost:6789/ in your browser.

This code has been tested on Ubuntu Linux, but should work on other platforms
that Shiny supports.

Both of these apps use the underlying analysis code in `analysis/R`, just like
the command line demo `demo.sh` does.

rappor-analysis
---------------

This app "decodes" a RAPPOR data set.  In other words, you can upload the
`params`, `counts`, and `map` files, and view the inferred distribution, as
well as debug info.

These files are discussed in the RAPPOR [Data Flow][data-flow] doc.

rappor-sim
----------

This app lets you simulate RAPPOR runs with different populations and
parameters.  This can help you choose collection parameters for a given
situation / variable.

Help
----

If you need help with these apps, please send a message to
[rappor-discuss][group].


[shiny]: http://shiny.rstudio.com/ 
[rstudio]: http://rstudio.com/ 
[data-flow]: http://google.github.io/rappor/doc/data-flow.html
[group]: https://groups.google.com/forum/#!forum/rappor-discuss
