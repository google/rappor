Command Line Tools
==================

This directory contains command line tools for RAPPOR analysis.

decode-dist
-----------

Decode a distribution -- requires a "counts" file (summed bits from reports),
map file, and a params file.  See `test.sh decode-dist` in this dir for an
example.

decode-assoc
------------

Decode a joint distribution between 2 variables ("association analysis").  See
`test.sh decode-assoc` in this dir for an example.

Currently it only supports associating strings vs. booleans.

Setup
-----

Both of these tools are written in R, and require several R libraries to be
installed (see `../setup.sh r-packages`).

`decode-assoc` also shells out to a native binary written in C++ if
`--em-executable` is passed.  This requires a C++ compiler (see
`analysis/cpp/run.sh`).  You can run `test.sh decode-assoc-cpp` to test it.

