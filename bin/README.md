Command Line Tools
==================

This directory contains command line tools for RAPPOR analysis.

Analysis Tools
--------------

### decode-dist

Decode a distribution -- requires a "counts" file (summed bits from reports),
map file, and a params file.  See `test.sh decode-dist` in this dir for an
example.

### decode-assoc

Decode a joint distribution between 2 variables ("association analysis").  See
`test.sh decode-assoc-R` or `test.sh decode-assoc-cpp` in this dir for an
example.

Currently it only supports associating strings vs. booleans.

### Setup

Both of these tools are written in R, and require several R libraries to be
installed (see `../setup.sh r-packages`).

`decode-assoc` also shells out to a native binary written in C++ if
`--em-executable` is passed.  This requires a C++ compiler (see
`analysis/cpp/run.sh`).  You can run `test.sh decode-assoc-cpp` to test it.


Helper Tools
------------

These are simple Python implementations of tools needed for analysis.  At
Google, Chrome uses alternative C++/Go implementations of these tools.

### sum-bits

Given a CSV file with RAPPOR reports (IRRs), produce a "counts" CSV file on
stdout.  This is the `m x (k+1)` matrix that is used in the R analysis (where m
= #cohorts and k = report width in bits).

### hash-candidates

Given a list of candidates on stdin, produce a CSV file of hashes (the "map
file").  Each row has `m x h` cells (where m = #cohorts and h = #hashes)

See the `regtest.sh` script for examples of how these tools are invoked.

