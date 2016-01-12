// Copyright 2015 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <assert.h>
#include <stdarg.h>  // va_list, etc.
#include <stdio.h>  // fread()
#include <stdlib.h>  // exit()
#include <stdint.h>  // uint16_t
#include <string.h>  // strcmp()
#include <cmath>  // std::abs operates on doubles
#include <cstdlib>  // strtol
#include <vector>

using std::vector;

// Log messages to stdout.
void log(const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vprintf(fmt, args);
  va_end(args);
  printf("\n");
}

const int kTagLen = 4;  // 4 byte tags in the file format

bool ExpectTag(FILE* f, const char* tag) {
  char buf[kTagLen];

  if (fread(buf, sizeof buf[0], kTagLen, f) != kTagLen) {
    return false;
  }
  if (strcmp(buf, tag) != 0) {
    log("Error: expected '%s'", tag);
    return false;
  }
  return true;
}

static bool ReadListOfMatrices(
    FILE* f, uint32_t* num_entries_out, uint32_t* entry_size_out,
    vector<double>* v_out) {
  if (!ExpectTag(f, "ne ")) {
    return false;
  }

  // R integers are serialized as uint32_t
  uint32_t num_entries;
  if (fread(&num_entries, sizeof num_entries, 1, f) != 1) {
    return false;
  }

  log("num entries: %d", num_entries);

  if (!ExpectTag(f, "es ")) {
    return false;
  }

  uint32_t entry_size;
  if (fread(&entry_size, sizeof entry_size, 1, f) != 1) {
    return false;
  }
  log("entry_size: %d", entry_size);

  if (!ExpectTag(f, "dat")) {
    return false;
  }

  // Now read dynamic data
  size_t vec_length = num_entries * entry_size;

  vector<double>& v = *v_out;
  v.resize(vec_length);

  if (fread(&v[0], sizeof v[0], vec_length, f) != vec_length) {
    return false;
  }

  // Print out head for sanity
  size_t n = 20;
  for (size_t i = 0; i < n && i < v.size(); ++i) {
    log("%d: %f", i, v[i]);
  }

  *num_entries_out = num_entries;
  *entry_size_out = entry_size;

  return true;
}

void PrintEntryVector(const vector<double>& cond_prob, size_t m,
                      size_t entry_size) {
  size_t c_base = m * entry_size;
  log("cond_prob[m = %d] = ", m);
  for (size_t i = 0; i < entry_size; ++i) {
    printf("%e ", cond_prob[c_base + i]);
  }
  printf("\n");
}

void PrintPij(const vector<double>& pij) {
  double sum = 0.0;
  printf("PIJ:\n");
  for (size_t i = 0; i < pij.size(); ++i) {
    printf("%f ", pij[i]);
    sum += pij[i];
  }
  printf("\n");
  printf("SUM: %f\n", sum);  // sum is 1.0 after normalization
  printf("\n");
}

// EM algorithm to iteratively estimate parameters.

static int ExpectationMaximization(
    uint32_t num_entries, uint32_t entry_size, const vector<double>& cond_prob,
    int max_em_iters, double epsilon, vector<double>* pij_out) {
  // Start out with uniform distribution.
  vector<double> pij(entry_size, 0.0);
  double init = 1.0 / entry_size;
  for (size_t i = 0; i < pij.size(); ++i) {
    pij[i] = init;
  }
  log("Initialized %d entries with %f", pij.size(), init);

  vector<double> prev_pij(entry_size, 0.0);  // pij on previous iteration

  log("Starting up to %d EM iterations", max_em_iters);

  int em_iter = 0;  // visible after loop
  for (; em_iter < max_em_iters; ++em_iter) {
    //
    // lapply() step.
    //

    // Computed below as a function of old Pij and conditional probability for
    // each report.
    vector<double> new_pij(entry_size, 0.0);

    // m is the matrix index, giving the conditional probability matrix for a
    // single report.
    for (size_t m = 0; m < num_entries; ++m) {
      vector<double> z(entry_size, 0.0);

      double sum_z = 0.0;

      // base index for the matrix corresponding to a report.
      size_t c_base = m * entry_size;

      for (size_t i = 0; i < entry_size; ++i) {  // multiply and running sum
        size_t c_index = c_base + i;
        z[i] = cond_prob[c_index] * pij[i];
        sum_z += z[i];
      }

      // Normalize and Reduce("+", wcp) step.  These two steps are combined for
      // memory locality.
      for (size_t i = 0; i < entry_size; ++i) {
        new_pij[i] += z[i] / sum_z;
      }
    }

    // Divide outside the loop
    for (size_t i = 0; i < entry_size; ++i) {
      new_pij[i] /= num_entries;
    }

    //PrintPij(new_pij);

    //
    // Check for termination
    //
    double max_dif = 0.0;
    for (size_t i = 0; i < entry_size; ++i) {
      double dif = std::abs(new_pij[i] - pij[i]);
      if (dif > max_dif) {
        max_dif = dif;
      }
    }

    pij = new_pij;  // copy

    log("fast EM iteration %d, dif = %e", em_iter, max_dif);

    if (max_dif < epsilon) {
      log("Early EM termination: %e < %e", max_dif, epsilon);
      break;
    }
  }

  *pij_out = pij;
  // If we reached iteration index 10, then there were 10 iterations: the last
  // one terminated the loop.
  return em_iter;
}

bool WriteTag(const char* tag, FILE* f_out) {
  assert(strlen(tag) == 3);  // write 3 byte tags with NUL byte
  return fwrite(tag, 1, 4, f_out) == 4;
}

// Write the probabilities as a flat list of doubles.  The caller knows what
// the dimensions are.
bool WriteResult(const vector<double>& pij, uint32_t num_em_iters,
                 FILE* f_out) {
  if (!WriteTag("emi", f_out)) {
    return false;
  }
  if (fwrite(&num_em_iters, sizeof num_em_iters, 1, f_out) != 1) {
    return false;
  }

  if (!WriteTag("pij", f_out)) {
    return false;
  }
  size_t n = pij.size();
  if (fwrite(&pij[0], sizeof pij[0], n, f_out) != n) {
    return false;
  }
  return true;
}

// Like atoi, but with basic (not exhaustive) error checking.
bool StringToInt(const char* s, int* result) {
  bool ok = true;
  char* end;  // mutated by strtol

  *result = strtol(s, &end, 10);  // base 10
  // If strol didn't consume any characters, it failed.
  if (end == s) {
    ok = false;
  }
  return ok;
}

int main(int argc, char **argv) {
  if (argc < 4) {
    log("Usage: read_numeric INPUT OUTPUT max_em_iters");
    return 1;
  }

  char* in_filename = argv[1];
  char* out_filename = argv[2];

  int max_em_iters;
  if (!StringToInt(argv[3], &max_em_iters)) {
    log("Error parsing max_em_iters");
    return 1;
  }

  FILE* f = fopen(in_filename, "rb");
  if (f == NULL) {
    return 1;
  }

  // Try opening first so we don't do a long computation and then fail.
  FILE* f_out = fopen(out_filename, "wb");
  if (f_out == NULL) {
    return 1;
  }

  uint32_t num_entries;
  uint32_t entry_size;
  vector<double> cond_prob;
  if (!ReadListOfMatrices(f, &num_entries, &entry_size, &cond_prob)) {
    log("Error reading list of matrices");
    return 1;
  }

  fclose(f);

  // Sanity check
  double debug_sum = 0.0;
  for (size_t m = 0; m < num_entries; ++m) {
    // base index for the matrix corresponding to a report.
    size_t c_base = m * entry_size;
    for (size_t i = 0; i < entry_size; ++i) {  // multiply and running sum
      debug_sum += cond_prob[c_base + i];
    }
  }
  log("Debug sum: %f", debug_sum);

  double epsilon = 1e-6;
  log("epsilon: %f", epsilon);

  vector<double> pij(entry_size);
  int num_em_iters = ExpectationMaximization(
      num_entries, entry_size, cond_prob, max_em_iters, epsilon, &pij);

  if (!WriteResult(pij, num_em_iters, f_out)) {
    log("Error writing result matrix");
    return 1;
  }
  fclose(f_out);

  log("fast EM done");
  return 0;
}
