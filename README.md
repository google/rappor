RAPPOR
======

RAPPOR is a novel privacy technology that allows inferring statistics of
populations while preserving the privacy of individual users.

This repository currently contains simulation and analysis code in Python and
R.

For a detailed description of the algorithm, see the
[paper](http://arxiv.org/abs/1407.6981) and links below.

<!-- TODO: We should have a more user friendly non-mathematical explanation?
-->

Running the Demo
----------------

Although the Python and R libraries should be portable to any platform, our
end-to-end demo has only been tested on Linux .

If you don't have a Linux box handy, you can [view the generated
output](report.html).

To get your feet wet, install the R dependencies (details below), which should
look something like this:

    $ R
    ...
    > install.packages(c('glmnet', 'optparse', 'ggplot2'))

Then run:

    $ ./demo.sh build  # optional speedup, it's OK for now if it fails
    $ ./demo.sh run

The `build` action compiles and tests the optional `fastrand` C extension
module for Python, which speeds up the simulation.

The `run` action strings together the Python and R code.  It:

1. Generates simulated input data with different distributions
2. Runs it through the RAPPOR privacy algorithm
3. Analyzes and plots the obfuscated reports against the true input

The output is written to `_tmp/report.html`, and can be opened with a browser.

<!-- TODO: Link to Github pages version of report.html. -->

Dependencies
------------

[R](http://r-project.org) analysis (`analysis/R`):

- [glmnet](http://cran.r-project.org/web/packages/glmnet/index.html)

Demo dependencies (`demo.sh`):

These are necessary if you want to test changes to the code.

- R libraries
  - [ggplot2](http://cran.r-project.org/web/packages/ggplot2/index.html)
  - [optparse](http://cran.r-project.org/web/packages/optparse/index.html)
- bash shell / coreutils: to run tests

Python client (`client/python`):

- None.  You should be able to just import the `rappor.py` file.

Platform:

- R: tested on R 3.0.
- Python: tested on Python 2.7.
- OS: the shell script tests have been tested on Linux, but may work on
  Mac/Cygwin.  The R and Python code should work on any OS.

API
---

`rappor.py` is a tiny standalone Python file, and you can easily copy it into a
Python program.

NOTE: Its interface is subject to change.  We are in the demo stage now, but if
there's demand, we will document and publish the interface.

The R interface is also subject to change.

<!-- TODO: Add links to interface docs when available. -->

The `fastrand` C module is optional.  It's likely only useful for simulation of
thousands of clients.  It doesn't use crytographically strong randomness, and
thus should **not** be used in production.

Directory Structure
-------------------

    client/             # client libraries
      python/
        rappor.py
        rappor_test.py  # unit tests next to files
      cpp/              # placeholder
    analysis/
      R/
        # R code for analysis.
    tests/              # for system tests.  Unit tests should go next to the
                        # source file.
      gen_sim_input.py  # generate test input data
      rappor_sim.py     # run simulation
      run.sh            # driver for unit tests, lint, statistical tests,
                        # end to end demo with Python/R
    doc/
    build.sh            # build docs or C code
    demo.sh             # run deom

<!--
TODO: add apps?

    apps/
      # Shiny apps for demo.  Depends on the analysis code.
-->

Links
-----

<!-- TODO: link back to blog post -->

- [Tutorial](doc/tutorial.html) - More details about the tools here.
- [RAPPOR paper](http://arxiv.org/abs/1407.6981)
- [RAPPOR implementation in Chrome](http://www.chromium.org/developers/design-documents/rappor)
  - This is a production quality C++ implementation, but it's somewhat tied to
    Chrome, and doesn't support all privacy parameters (e.g. only a few values
    of p and q).  On the other hand, the code in this repo is not yet
    production quality, but supports experimentation with different parameters
    and data sets.  Of course, anyone is free to implement RAPPOR independently
    as well.

