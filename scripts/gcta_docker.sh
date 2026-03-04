#!/usr/bin/env bash
set -euo pipefail

# Wrapper for RAP Swiss Army Knife sessions where GCTA is used via Docker.
IMAGE="${GCTA_IMAGE:-quay.io/biocontainers/gcta:1.94.1--h9ee0642_0}"

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <gcta64 arguments>"
  echo "Example: $0 --help"
  exit 1
fi

docker run --rm \
  -u "$(id -u):$(id -g)" \
  -w "$PWD" \
  -v "$PWD":"$PWD" \
  "$IMAGE" gcta64 "$@"
