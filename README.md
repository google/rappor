RAPPOR
======

RAPPOR is a novel privacy technology that allows inferring statistics about
populations while preserving the privacy of individual users.

This repository contains simulation and analysis code in Python and R.

For a detailed description of the algorithms, see the
[paper](http://arxiv.org/abs/1407.6981) and links below.

Feel free to send feedback to
[rappor-discuss@googlegroups.com][group].

Running the Demo
----------------

Although the Python and R libraries should be portable to any platform, our
end-to-end demo has only been tested on Linux.

If you don't have a Linux box handy, you can [view the generated
output](http://google.github.io/rappor/examples/report.html).

To get your feet wet, install the R dependencies (details below).  It should
look something like this:

    $ R
    ...
    > install.packages(c('glmnet', 'optparse', 'ggplot2'))

Then run:

    $ ./demo.sh build  # optional speedup, it's OK for now if it fails

This compiles and tests the `fastrand` C extension module for Python, which
speeds up the simulation.

    $ ./demo.sh run

The demo strings together the Python and R code.  It:

1. Generates simulated input data with different distributions
2. Runs it through the RAPPOR privacy-preserving reporting mechanisms
3. Analyzes and plots the aggregated reports against the true input

The output is written to `_tmp/report.html`, and can be opened with a browser.

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

Development
-----------

To run tests:

    $ ./test.sh all

This currently runs Python unit tests, lints Python source files, and runs R
unit tests.

API
---

`rappor.py` is a tiny standalone Python file, and you can easily copy it into a
Python program.

NOTE: Its interface is subject to change.  We are in the demo stage now, but if
there's demand, we will document and publish the interface.

The R interface is also subject to change.

<!-- TODO: Add links to interface docs when available. -->

The `fastrand` C module is optional.  It's likely only useful for simulation of
thousands of clients.  It doesn't use cryptographically strong randomness, and
thus should **not** be used in production.

Directory Structure
-------------------

    client/             # client libraries
      python/
        rappor.py
        rappor_test.py  # Unit tests go next to the implementation.
      cpp/              # placeholder
    analysis/
      R/                # R code for analysis
      tools/            # command line tools for analysis
    apps/               # web apps to help you use RAPPOR
    tests/              # system tests
      gen_sim_input.py  # generate test input data
      rappor_sim.py     # run simulation
      run.sh            # driver for unit tests, lint
    doc/
    build.sh            # build docs, C extension
    demo.sh             # run demo
    run.sh              # misc automation

<!--
TODO: add apps?

    apps/
      # Shiny apps for demo.  Depends on the analysis code.
-->

Documentation
-------------

- [RAPPOR Data Flow](http://google.github.io/rappor/doc/data-flow.html)

Publications
------------

- [RAPPOR: Randomized Aggregatable Privacy-Preserving Ordinal Response](http://arxiv.org/abs/1407.6981)
- [Building a RAPPOR with the Unknown: Privacy-Preserving Learning of Associations and Data Dictionaries](http://arxiv.org/abs/1503.01214)

Links
-----

- [Google Blog Post about RAPPOR](http://googleresearch.blogspot.com/2014/10/learning-statistics-with-privacy-aided.html)
- [RAPPOR implementation in Chrome](http://www.chromium.org/developers/design-documents/rappor)
  - This is a production quality C++ implementation, but it's somewhat tied to
    Chrome, and doesn't support all privacy parameters (e.g. only a few values
    of p and q).  On the other hand, the code in this repo is not yet
    production quality, but supports experimentation with different parameters
    and data sets.  Of course, anyone is free to implement RAPPOR independently
    as well.
- Mailing list: [rappor-discuss@googlegroups.com][group]

[group]: https://groups.google.com/forum/#!forum/rappor-discuss
