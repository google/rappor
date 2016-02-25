RAPPOR Clients
==============

This directory contains RAPPOR client implementations in various languages.

The privacy of RAPPOR is based on the client "lying" about the true values --
that is, not sending them over the network.

The clients are typically small in terms of code size because the RAPPOR
client algorithm is simple.  See the README.md in each subdirectory for details
on how to use the library.

Common Test Protocol
--------------------

When implementing a new RAPPOR client, you can get for free!

The `regtest.sh` script in the root of this repository does the following:

1. Create test input data and feed it into your client as a CSV file
2. Preprocesses your client output (also CSV)
3. Runs the RAPPOR analysis, learning aggregate statistics from encoded values
4. Compares the analysis to the true client values, with metrics and plots.

To have your client tested, you need a small executable wrapper, which reads
and write as CSV file in a specified format.

Then add it to the `_run-one-instance` function in `regtest.sh`. 

<!--

TODO:
-  more details about protocol

-->








