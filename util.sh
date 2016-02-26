#!/bin/bash
#
# Utility functions, used by demo.sh and regtest.sh.

banner() {
  echo
  echo "----- $@"
  echo
}

log() {
  echo 1>&2 "$@"
}

die() {
  log "$0: $@"
  exit 1
}

