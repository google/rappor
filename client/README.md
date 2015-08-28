RAPPOR Clients
==============

This directory contains RAPPOR client implementations, which you can link into
programs written in various languages.

The privacy of RAPPOR is based on the client "lying" about the true values --
that is, not sending them over the network.

See the README.md in each subdirectory for details on how to use the library.

Common Test Protocol
--------------------

When implementing a new RAPPOR client, you can get tests for free!

The `regtest.sh` script in the root of this repository does the following:

1) Create test input data and feed it into your client as a CSV file
2) Runs the RAPPOR analysis, learning aggregate statistics from encoded values
3) Compares the analysis to the true client values, with metrics and plots

<!-- TODO: more details -->








