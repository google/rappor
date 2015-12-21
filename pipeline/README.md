pipeline
========

This directory contains tools and scripts for running a cron job that does
RAPPOR analysis and generates an HTML dashboard.

It works like this:

1. `task_spec.py` generates a text file where each line corresponds to a process
   to be run (a "task").  The process is `bin/decode-dist` or
   `bin/decode-assoc`.  The line contains the task parameters.

2. `xargs -P` is used to run processes in parallel.  Our analysis is generally
   single-threaded (i.e. because R is single-threaded), so this helps utilize
   the machine fully.  Each task places its output in a different subdirectory.

3. `cook.sh` calls `combine_results.py` to combine analysis results into a time
   series.  It also calls `combine_status.py` to keep track of task data for
   "meta-analysis".  `metric_status.R` generates more summary CSV files.

4. `ui.sh` calls `csv_to_html.py` to generate an HTML fragments from the CSV
   files.

5. The JavaScript in `ui/ui.js` is loaded from static HTML, and makes AJAX calls
   to retrieve the HTML fragments.  The page is made interactive with
   `ui/table-lib.js`.

`dist.sh` and `assoc.sh` contain functions which coordinate this process.

`alarm-lib.sh` is used to kill processes that have been running for too long.

Testing
-------

`pipeline/regtest.sh` contains end-to-end demos of this process.  Right now it
depends on testdata from elsewhere in the tree:


    rappor$ ./demo.sh run   # prepare dist testdata
    rappor$ cd bin

    bin$ ./test.sh write-assoc-testdata  # prepare assoc testdata
    bin$ cd ../pipeline
    
    pipeline$ ./regtest.sh dist
    pipeline$ ./regtest.sh assoc

    pipeline$ python -m SimpleHTTPServer  # start a static web server
    
    http://localhost:8000/_tmp/


