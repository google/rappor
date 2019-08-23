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

To setup your environment there are some packages and R dependencies. There is a setup script to install them:
    $ ./setup.sh
Then to build the native components run:
    $ ./build.sh 
This compiles and tests the `fastrand` C extension module for Python, which
speeds up the simulation.

Finally to run the demo run:
    $ ./demo.sh

The demo strings together the Python and R code.  It:

1. Generates simulated input data with different distributions
2. Runs it through the RAPPOR privacy-preserving reporting mechanisms
3. Analyzes and plots the aggregated reports against the true input

The output is written to `_tmp/regtest/results.html`, and can be opened with a
browser.

Dependencies
------------

[R](http://r-project.org) analysis (`analysis/R`):

- [glmnet](http://cran.r-project.org/web/packages/glmnet/index.html)
- [limSolve](https://cran.r-project.org/web/packages/limSolve/index.html)

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

    $ ./test.sh

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

    analysis/
      R/                 # R code for analysis
      cpp/               # Fast reimplementations of certain analysis
                         #   algorithms
    apps/                # Web apps to help you use RAPPOR (using Shiny)
    bin/                 # Command line tools for analysis.
    client/              # Client libraries
      python/            # Python client library
        rappor.py
        ...
      cpp/               # C++ client library
        encoder.cc
        ...
    doc/                 # Documentation
    tests/               # Tools for regression tests
      compare_dist.R     # Test helper for single variable analysis
      gen_true_values.R  # Generate test input
      make_summary.py    # Generate an HTML report for the regtest
      rappor_sim.py      # RAPPOR client simulation
      regtest_spec.py    # Specification of test cases
      ...
    build.sh             # Build scripts (docs, C extension, etc.)
    demo.sh              # Quick demonstration
    docs.sh              # Generate docs form the markdown in doc/
    gh-pages/            # Where generated docs go. (A subtree of the branch gh-pages)
    pipeline/            # Analysis pipeline code.
    regtest.sh           # End-to-end regression tests, including client
                         #  libraries and analysis
    setup.sh             # Install dependencies (for Linux)
    test.sh              # Test runner

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
