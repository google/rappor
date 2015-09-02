Command Line Tools
==================

This directory contains command line tools for analysis.

decode-dist
-----------

Decode a distribution -- requires a "counts" file (summed bits from reports),
map file, and a params file.  See `test.sh` in this dir for an example.  This
tool is written in R, and requires several R libraries to be installed (see
`../setup.sh r-packages`).
