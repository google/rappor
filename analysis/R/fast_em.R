# fast_em.R: Wrapper around analysis/cpp/fast_em.cc.
#
# This serializes the input, shells out, and deserializes the output.

.Flatten <- function(list_of_matrices) {
  listOfVectors <- lapply(list_of_matrices, as.vector)
  #print(listOfVectors)

  # unlist takes list to vector.
  unlist(listOfVectors)
}

.WriteListOfMatrices <- function(list_of_matrices, f) {
  flattened <- .Flatten(list_of_matrices)

  # NOTE: UpdateJointConditional does outer product of dimensions!

  # 3 letter strings are null terminated
  writeBin('ne ', con = f)
  num_entries <- length(list_of_matrices)
  writeBin(num_entries, con = f)

  Log('Wrote num_entries = %d', num_entries)

  # For 2x3, this is 6
  writeBin('es ', con = f)

  entry_size <- as.integer(prod(dim(list_of_matrices[[1]])))
  writeBin(entry_size, con = f)

  Log('Wrote entry_size = %d', entry_size)

  # now write the data
  writeBin('dat', con = f)
  writeBin(flattened, con = f)
}

# Display some stats before sending it over to C++.
.SanityChecks <- function(joint_conditional) {
    # Sanity checks

    inf_counts <- lapply(joint_conditional, function(m) {
      sum(m == Inf)
    })
    total_inf <- sum(as.numeric(inf_counts))

    nan_counts <- lapply(joint_conditional, function(m) {
      sum(is.nan(m))
    })
    total_nan <- sum(as.numeric(nan_counts))

    zero_counts <- lapply(joint_conditional, function(m) {
      sum(m == 0.0)
    })
    total_zero <- sum(as.numeric(zero_counts))

    #sum(joint_conditional[joint_conditional == Inf, ])
    Log('total inf: %s', total_inf)
    Log('total nan: %s', total_nan)
    Log('total zero: %s', total_zero)
}

ConstructFastEM <- function(em_executable, tmp_dir) {
  # TODO:
  # - check that number of dimensions is 2
  # - Serialize joint_conditional.  This is the outer product thingy.
  #   - Or maybe you can do an array of cond_report_dist, and then do outer
  #   product in C++

  return(function(joint_conditional, max_em_iters = 1000,
                  epsilon = 10 ^ -6, verbose = FALSE,
                  estimate_var = FALSE) {
    entry_size <- prod(dim(joint_conditional[[1]]))
    Log('entry size: %d', entry_size)

    .SanityChecks(joint_conditional)

    input_path <- file.path(tmp_dir, 'list_of_matrices.bin')
    Log("Writing flattened list of matrices to %s", input_path)
    f <- file(input_path, 'wb')  # binary file
    .WriteListOfMatrices(joint_conditional, f)
    close(f)
    Log("Done writing %s", input_path)
     
    output_path <- file.path(tmp_dir, 'pij.bin')

    cmd <- sprintf("%s %s %s %s", em_executable, input_path, output_path,
                   max_em_iters)
    Log("Shell command: %s", cmd)
    system(cmd)
    Log("Done running shell command")

    pij <- readBin(con = output_path, what = "double", n = entry_size)

    # Adjust dimensions
    dim(pij) <- dim(joint_conditional[[1]])

    Log("PIJ read from C++:")
    print(pij)
     
    # est, sd, var_cov, hist
    list(est = pij)
  })
}
