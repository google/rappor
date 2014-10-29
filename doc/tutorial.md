(under construction)

RAPPOR Tutorial
===============

This doc explains the simulation tools for RAPPOR.  For a detailed description
of the algorithm, see the [paper](http://arxiv.org/abs/1407.6981).

Start with this command:

    $ ./demo.sh run

It takes a minute or so to run.  The dependencies listed in the
[README](../README.html) must be installed.

This command generates simulated input data with different distributions, runs
it through RAPPOR, then analyzes and plots the output.


1. Generating Simulated Input Data
----------------------------------

`gen_sim_input.py` generates test data.  Each row contains a client ID, and a
space separated list of reported values -- the true values we wish to keep
private.

By default, we generate 5-9 values per client, out of 50 unique values, so the
output may look something like this:

    1,s10 s55 s1 s15 s29 s57 s6
    2,s20 s61 s9 s21 s39 s32 s32 s6 s49
    ...
    <client N>,<client N's space-separated raw data>

You can select the distribution of the `sN` values by passing a flag.  The
shell script loops through 3 distributions: exponential, normal/gaussian, and
uniform.

You can also write a script to generate a file in this format and pass it to
the next two stages.

2. RAPPOR Transformation
------------------------

`tests/rappor_sim.py` uses the Python client library
(`client/python/rappor.py`) to obfuscate the `s1` .. `sN` strings.

To preserve the user's privacy, we add random noise by flipping bits in two
different ways.

<!-- TODO: a realistic data set would be nice? How could we generate one?  -->

It generates 4 files:

- Counts (`exp_out.csv`) -- This currently is the sum of what will be sent over
  the network.  TODO: change it to output individual reports.  Then have a
  separate tool that does the summing.

- Parameters (`exp_params.csv`) -- This is a 1-row CSV file with the 6 privacy parameters
  `k,h,m,p,q,f`. (The [report.html](../report.html) file and the paper both
  describe these parameters).  This should be sent over the network along with
  the counts.  When the raw RAPPOR data is persisted, this should also form
  part of the "schema", as the data can't be decoded correctly without it.

- True histogram of input values (`exp_hist.csv`) -- This is for debugging /
  comparison.  You won't have this in a real setting, of course.

- Map file (`exp_map.csv`) -- Hashed candidates.  


3. RAPPOR Analysis
------------------

Once you have the `counts`, `params`, and `map` files, you can pass it to the
`tests/analyze.R` tool, which is a small wrapper around the `analyze/R`
library.

Then you will get a plot of the true distribution vs. the distribution
recovered from data obfuscated with the RAPPOR privacy algorithm.

[View the example output](../report.html).

You can change the simulation or RAPPOR parameters via flags, and compare the
resulting distributions.

TODO
----

The user should provide candidates, and we should have tool to hash them.  This
is like the gen_map tool.

    $ hash_candidates.py <candidates>
    (Writes <map file>)

Tool to extract candidates from the input file.

    $ ./demo.sh cheat-candidates <raw input>

In the real setting, it can be nontrivial to enumerate the candidates.

To simulate this, filter the list with `grep`.

Show more detailed command lines, --help?

