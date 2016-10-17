RAPPOR Data Flow
================

This doc explains the simulation tools and data formats in the [RAPPOR
repository](https://github.com/google/rappor).  We'll focus on the code, and
describe the algorithm only informally.  For details, see the [paper][].

Overview
--------

Start with this command:

    $ ./demo.sh

It takes a minute or so to run.  The dependencies listed in the
[README][] must be installed.  At the end, it will say:

    Wrote _tmp/\[cpp and python\]/results.html.  Open this in your browser.

It should look like [this][example].

The following diagram shows what processes and files are involved in the demo.
Ovals represent **processes**; rectangles represent **data**.  The dotted lines
denote components that are involved in the simulation, but wouldn't be used in
a "real" setting.

In most configurations, reporting (in blue) is done by client machines, while
analysis (in green) is done by a server.

<img src="data-flow.png" alt="Diagram of RAPPOR Data Flow" />

In the simulation, reporting consists of these steps:

  1. Generate simulated input data with different distributions.
  2. Obscure each value with the RAPPOR privacy-preserving reporting mechanism.

Analysis consists of these steps:

  1. Aggregate the reports by summing bits (i.e. make a counting Bloom filter)
  2. Come up with candidate strings, and hash them in the same manner as the
  client.
  3. Using the reports, RAPPOR parameters, and candidate strings as input,
  infer the distribution of true values.  We don't see the values themselves.
  We plot the true and inferred distributions side by side for comparison.

This process is described in detail below.

1. Generating Simulated Input
-----------------------------

The `tests/gen_sim_input.py` tool generates CSV data, like this:

<!-- TODO: a realistic data set would be nice? How could we generate one?  -->

**case_true_values.csv**
```
client,cohort,value
c1,1,v16
c1,1,v13
c1,1,v19
c1,1,v16
c1,1,v2
c1,1,v31
c1,1,v8
c1,1,v19
c1,1,v13
c1,1,v21
c2,2,v58
c2,2,v4
c2,2,v26
c2,2,v22
c2,2,v20
c2,2,v2
    ...
```
*(spaces added for clarity)*

By default we generate 700,000 rows: 7 random values from `v1` to `v50` for
each client.  These can be thought of as a variable being reported over time.

We're simulating an environment where there are many RAPPOR clients, and a
single server does the RAPPOR analysis on the accumulated data.

The `client` is represented by an integer ID.  The `true_value` should **not**
be sent over the network because we wish to preserve the client's privacy.


2. RAPPOR Reporting
-------------------

The `tests/rappor_sim.py` tool uses the Python client library
(`client/python/rappor.py`) to obscure the `v1` .. `vN` strings.  We want to
infer the distribution of these strings over the entire population, but we
don't want to know any individual values.

After the RAPPOR transformation, we get another CSV file with 700,000 rows.
Each client is assigned a cohort.

**case_reports.csv**
```
client,cohort,bloom,prr,irr
c1,1,00000000000000000010000000000000,11011100100000000010000101100001,01001101100000000010000111000010
c1,1,00000000000000001000000000000000,00011011010000101010010000010100,00011011000001100010010000011100
c1,1,10000000000000000000000000000000,10101000001110000000000000010000,00101010010111101000010100010000
c1,1,00000000000000000010000000000000,11011100100000000010000101100001,10011000100101101110000101100000
c1,1,00000000000000000000000000000001,00100100000000000100001000000100,01000010100100010000011000101101
c1,1,00010000000000000000000000000000,00010001000100000100000011000010,10001001000100001110010011000000
c1,1,00000000010000000000000000000000,00000010001000000001100000101110,10011110001000000101100100101110
c1,1,10000000000000000000000000000000,10101000001110000000000000010000,10101101101110000000000000010000
c1,1,00000000000000001000000000000000,00011011010000101010010000010100,00011011010001101010110110110100
c1,1,00000000010000000000000000000000,00000010001000000001100000101110,00001110001000000001110100101111
c2,2,00000000000010000000000000000000,10011001001000110001000001000000,10011111011011111000000011001010
c2,2,00000000000100000000000000000000,01100000000100000001001000000010,11110000110010010000001010001110
c2,2,00000000000000000000000000001000,10001010101000000000100000001000,00001010101000000100000110101000
    ...
```
*(spaces added for clarity)*

We also get a one-row CSV file that contains the RAPPOR parameters:

**case_params.csv**
```
k,h,m,p,q,f
32,1,64,0.25,0.75,0.5
```
These are described in the [paper][]. The parameters that the clients use
must be known to the server, or the decoding will fail.  In addition, all
clients must use the same parameters for a given variable.

The `rappor_sim.py` process also writes these files:

- `exp_hist.csv`: The true histogram of input values.  This is used only for
  comparison.  In the real world you obviously won't have this.
- `case_unique_values.txt`: A list of the unique values reported, e.g. `v1` ..
  `v50`.  You won't have this either, in general.  To use RAPPOR, you must
  supply *candidate strings*, described below.

3. Report Aggregation
---------------------

`sum_bits.py` takes the `exp_out.csv` output, and produces the "counts" file:

**case_counts.csv**
```
16170,6268,6102,6187,6143,6414,6090,6032,6454,6013,6105,6086,6399,6093,6265,6256,6167,6049,6110,6188,6348,6190,6131,6163,6035,6568,6123,6399,6094,6048,6295,6227,6310
15630,6215,5966,5878,6016,5881,5976,5985,5950,6121,5781,5974,5985,5988,6143,5799,6196,5795,5928,6409,5938,6100,5917,6067,5878,6033,5903,6152,5835,6058,5874,5860,5974
15500,6040,5910,5741,6103,6075,5826,5972,5892,6078,5953,5978,5957,5813,5739,6079,5915,5931,6076,6072,5991,6010,5768,5887,5830,6003,5887,5980,5873,5806,5915,5971,6027
    ...
```

The file has 64 rows, because the simulation has 64 cohorts by default (`m =
64`).  This parameter should be adjusted based on the number of unique true
values expected.  <!-- TODO: more detail -->

There are 1+32 columns.  The left-most column is the total number of reports in
the cohort.  The remaining 16 columns correspond to the `k = 16` bits in the
Bloom filter.  Each column contains the number of reports with that bit set
to 1.

So, in general, the "counts" file is a `(k+1) * m` matrix.

4. Candidate Strings
--------------------

In the simulation, we assume that the analyst will come up with a *superset* of
the candidate strings.  This is done in the `more-candidates` /
`print-candidates` functions in `regtest.sh`.

You can also test what happens if you omit true strings from the candidates, by
editing the invocation of `print-candidates` in `run-dist`:

    # Example of omitting true values.  Generate candidates from
    # exp_true_inputs.txt, omitting values v1 and v2.

    print-candidates $dist 'v1|v2'  > _tmp/${dist}_candidates.txt

In general, coming up with candidates is an application- or metric-specific
process.

The candidates are hashed by `hash_candidates.py` to create the "map" file,
before being passed to R for analysis.

**case_map.csv**

    v1,8,13,30,22,37,37,53,53,77,67,89,86,97,97,118,128,139,136,157,<truncated>
    v10,13,2,25,28,42,45,58,60,68,66,91,89,108,102,113,125,130,131,<truncated>

The map file has one row per candidate.  In this case, there are 200 rows: 
100 for the true values and 100 for "fake" values, which make the candidates a
superset of the true input.

The left most column is the raw candidate string.  Then there are 128 more
columns: for `m = 64` cohorts times `k = 2` hash functions in the Bloom filter.

<!-- TODO: more detail about setting params?  Examples of coming up with
candidate strings? -->

5. RAPPOR Analysis
------------------

Once you have the `counts`, `params`, and `map` files, you can pass it to the
`tests/analyze.R` tool, which is a small wrapper around the `analyze/R`
library.

You will get a plot of the true distribution vs. the distribution recovered
with the RAPPOR privacy algorithm.

[View the example output][example].

You can change the simulation parameters and RAPPOR parameters via flags, and
compare the resulting distributions.

For example, if you expect more unique values from clients, you should also use
more cohorts (i.e. raise `m`), to prevent hash function collisions from
degrading the result quality.

<!-- TODO: 
     - how to change flags
     - more detail on what the various parameters do
     - association analysis
     - basic RAPPOR
     - longitudinal privacy
-->

Conclusion
----------

RAPPOR allows you infer statistics about populations while preserving the
privacy of individual clients.  In this doc, we walked through a simple demo.
However, there are other variations of RAPPOR and settings in which you can use
RAPPOR, which we'll write more about.

Feel free to send feedback on this doc to
[rappor-discuss@googlegroups.com](https://groups.google.com/forum/#!forum/rappor-discuss).


[README]: https://github.com/google/rappor/blob/master/README.md
[paper]: http://arxiv.org/abs/1407.6981
[example]: http://google.github.io/rappor/examples/report.html

