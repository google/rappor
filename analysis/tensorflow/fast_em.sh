#!/bin/bash
#
# Wrapper to run fast_em.py using TensorFlow configured for a GPU.  CUDA
# environment variables must be set.
#
# Usage:
#   ./fast_em.sh <args>

set -o nounset
set -o pipefail
set -o errexit

readonly THIS_DIR=$(dirname $0)

fast-em() {
  # Never returns
  LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64 \
  CUDA_HOME=/usr/local/cuda-7.0 \
    exec $THIS_DIR/fast_em.py "$@"
}

fast-em "$@"
