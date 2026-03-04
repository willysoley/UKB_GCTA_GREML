#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run GREML one trait at a time using a trait list.

Usage:
  run_gcta_greml_all_traits.sh \
    --gcta gcta64 \
    --grm grm_prefix \
    --traits-file gcta_inputs/traits_to_run.txt \
    --input-dir gcta_inputs/traits \
    --threads 8 \
    --out-dir results
EOF
}

GCTA_BIN="gcta64"
GRM=""
TRAITS_FILE="gcta_inputs/traits_to_run.txt"
INPUT_DIR="gcta_inputs/traits"
THREADS="8"
OUT_DIR="results"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gcta) GCTA_BIN="$2"; shift 2 ;;
    --grm) GRM="$2"; shift 2 ;;
    --traits-file) TRAITS_FILE="$2"; shift 2 ;;
    --input-dir) INPUT_DIR="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$GRM" ]]; then
  echo "--grm is required" >&2
  usage
  exit 1
fi
if [[ ! -s "$TRAITS_FILE" ]]; then
  echo "Traits file not found or empty: $TRAITS_FILE" >&2
  exit 1
fi

while IFS= read -r trait; do
  [[ -z "$trait" ]] && continue
  echo "[GREML] Trait $trait"
  "$(dirname "$0")/run_gcta_greml_one_trait.sh" \
    --gcta "$GCTA_BIN" \
    --grm "$GRM" \
    --trait "$trait" \
    --input-dir "$INPUT_DIR" \
    --threads "$THREADS" \
    --out-dir "$OUT_DIR"
done < "$TRAITS_FILE"
