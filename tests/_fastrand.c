/*
Copyright 2014 Google Inc. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

/*
 * _fastrand.c -- Python extension module to generate random bit vectors
 * quickly.
 *
 * IMPORTANT: This module does not use crytographically strong randomness.  It
 * should be used ONLY be used to speed up the simulation.  Don't use it in
 * production.
 *
 * If an adversary can predict which random bits are flipped, then RAPPOR's
 * privacy is compromised.
 *
 */

#include <stdint.h>  // uint64_t
#include <stdio.h>  // printf
#include <stdlib.h>  // srand
#include <time.h>  // time

#include <Python.h>

uint64_t randbits(float p1, int num_bits) {
  uint64_t result = 0;
  // RAND_MAX is the maximum int returned by rand().
  //
  // When p1 == 1.0, we want to guarantee that all bits are 1.  The threshold
  // will be RAND_MAX + 1.  In the rare case that rand() returns RAND_MAX, the
  // "<" test succeeds, so we get 1.
  //
  // When p1 == 0.0, we want to guarantee that all bits are 0.  The threshold
  // will be 0.  In the rare case that rand() returns 0, the "<" test fails, so
  // we get 0.

  // NOTE: cast is necessary to do unsigned arithmetic rather than signed.
  // RAND_MAX is an int so adding 1 won't overflow a uint64_t.
  uint64_t max = (uint64_t)RAND_MAX + 1u;
  uint64_t threshold = p1 * max;
  int i;
  for (i = 0; i < num_bits; ++i) {
    // NOTE: The comparison is <= so that p1 = 1.0 implies that the bit is
    // ALWAYS set.  RAND_MAX is the maximum value returned by rand().
    uint64_t bit = (rand() < threshold);
    result |= (bit << i);
  }
  return result;
}

static PyObject *
func_randbits(PyObject *self, PyObject *args) {
  float p1;
  int num_bits;

  if (!PyArg_ParseTuple(args, "fi", &p1, &num_bits)) {
    return NULL;
  }
  if (p1 < 0.0 || p1 > 1.0) {
    printf("p1 must be between 0.0 and 1.0\n");
    // return None for now; easier than raising ValueError
    Py_INCREF(Py_None);
    return Py_None;
  }
  if (num_bits < 0 || num_bits > 64) {
    printf("num_bits must be 64 or less\n");
    // return None for now; easier than raising ValueError
    Py_INCREF(Py_None);
    return Py_None;
  }

  //printf("p: %f\n", p);
  uint64_t r = randbits(p1, num_bits);
  return PyLong_FromUnsignedLongLong(r);
}

PyMethodDef methods[] = {
  {"randbits", func_randbits, METH_VARARGS,
   "Return a number with N bits, where each bit is 1 with probability p."},
  {NULL, NULL},
};

void init_fastrand(void) {
  Py_InitModule("_fastrand", methods);

  // Just seed it here; we don't give the application any control.
  int seed = time(NULL);
  srand(seed);
}
