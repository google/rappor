#!/usr/bin/python
"""
fast_em.py: Tensorflow implementation of expectation maximization for RAPPOR
association analysis.

TODO:
  - Use TensorFlow ops for reading input (so that reading input can be
    distributed)
  - Reduce the number of ops (currently proportional to the number of reports).
    May require new TensorFlow ops.
  - Fix performance bug (v_split is probably being recomputed on every
    iteration):
    bin$ ./test.sh decode-assoc-cpp - 1.1 seconds (single-threaded C++)
    bin$ ./test.sh decode-assoc-tensorflow - 226 seconds on GPU
"""

import sys

import numpy as np
import tensorflow as tf


def log(msg, *args):
  if args:
    msg = msg % args
  print >>sys.stderr, msg


def ExpectTag(f, expected):
  """Read and consume a 4 byte tag from the given file."""
  b = f.read(4)
  if b != expected:
    raise RuntimeError('Expected %r, got %r' % (expected, b))


def ReadListOfMatrices(f):
  """
  Read a big list of conditional probability matrices from a binary file.
  """
  ExpectTag(f, 'ne \0')
  num_entries = np.fromfile(f, np.uint32, count=1)[0]
  log('Number of entries: %d', num_entries)

  ExpectTag(f, 'es \0')
  entry_size = np.fromfile(f, np.uint32, count=1)[0]
  log('Entry size: %d', entry_size)

  ExpectTag(f, 'dat\0')
  vec_length = num_entries * entry_size
  v = np.fromfile(f, np.float64, count=vec_length)

  log('Values read: %d', len(v))
  log('v: %s', v[:10])
  #print 'SUM', sum(v)

  # NOTE: We're not reshaping because we're using one TensorFlow tensor object
  # per matrix, since it makes the algorithm expressible with current
  # TensorFlow ops.
  #v = v.reshape((num_entries, entry_size))

  return num_entries, entry_size, v


def WriteTag(f, tag):
  if len(tag) != 3:
    raise AssertionError("Tags should be 3 bytes.  Got %r" % tag)
  f.write(tag + '\0')  # NUL terminated


def WriteResult(f, num_em_iters, pij):
  WriteTag(f, 'emi')
  emi = np.array([num_em_iters], np.uint32)
  emi.tofile(f)

  WriteTag(f, 'pij')
  pij.tofile(f)


def DebugSum(num_entries, entry_size, v):
  """Sum the entries as a sanity check."""
  cond_prob = tf.placeholder(tf.float64, shape=(num_entries * entry_size,))
  debug_sum = tf.reduce_sum(cond_prob)
  with tf.Session() as sess:
    s = sess.run(debug_sum, feed_dict={cond_prob: v})
  log('Debug sum: %f', s)


def BuildEmIter(num_entries, entry_size, v):
  # Placeholder for the value from the previous iteration.
  pij_in = tf.placeholder(tf.float64, shape=(entry_size,))

  # split along dimension 0
  # TODO:
  # - make sure this doesn't get run for every EM iteration
  # - investigate using tf.tile() instead?  (this may cost more memory)
  v_split = tf.split(0, num_entries, v)

  z_numerator = [report * pij_in for report in v_split]
  sum_z = [tf.reduce_sum(report) for report in z_numerator]
  z = [z_numerator[i] / sum_z[i] for i in xrange(num_entries)]

  # Concat per-report tensors and reshape.  This is probably inefficient?
  z_concat = tf.concat(0, z)
  z_concat = tf.reshape(z_concat, [num_entries, entry_size])

  # This whole expression represents an EM iteration.  Bind the pij_in
  # placeholder, and get a new estimation of Pij.
  em_iter_expr = tf.reduce_sum(z_concat, 0) / num_entries

  return pij_in, em_iter_expr


def RunEm(pij_in, entry_size, em_iter_expr, max_em_iters, epsilon=1e-6):
  """Run the iterative EM algorithm (using the TensorFlow API).

  Args:
    num_entries: number of matrices (one per report)
    entry_size: total number of cells in each matrix
    v: numpy.ndarray (e.g. 7000 x 8 matrix)
    max_em_iters: maximum number of EM iterations

  Returns:
    pij: numpy.ndarray (e.g. vector of length 8)
  """
  # Initial value is the uniform distribution
  pij = np.ones(entry_size) / entry_size

  i = 0  # visible outside loop

  # Do EM iterations.
  with tf.Session() as sess:
    for i in xrange(max_em_iters):
      print 'PIJ', pij
      new_pij = sess.run(em_iter_expr, feed_dict={pij_in: pij})
      dif = max(abs(new_pij - pij))
      log('EM iteration %d, dif = %e', i, dif)
      pij = new_pij

      if dif < epsilon:
        log('Early EM termination: %e < %e', max_dif, epsilon)
        break

  # If i = 9, then we did 10 iteratinos.
  return i + 1, pij


def sep():
  print '-' * 80


def main(argv):
  input_path = argv[1]
  output_path = argv[2]
  max_em_iters = int(argv[3])

  sep()
  with open(input_path) as f:
    num_entries, entry_size, cond_prob = ReadListOfMatrices(f)

  sep()
  DebugSum(num_entries, entry_size, cond_prob)

  sep()
  pij_in, em_iter_expr = BuildEmIter(num_entries, entry_size, cond_prob)
  num_em_iters, pij = RunEm(pij_in, entry_size, em_iter_expr, max_em_iters)

  sep()
  log('Final Pij: %s', pij)

  with open(output_path, 'wb') as f:
    WriteResult(f, num_em_iters, pij)
  log('Wrote %s', output_path)


if __name__ == '__main__':
  try:
    main(sys.argv)
  except RuntimeError, e:
    print >>sys.stderr, 'FATAL: %s' % e
    sys.exit(1)
