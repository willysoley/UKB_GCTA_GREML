#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run GREML for one trait prepared by prepare_gcta_inputs.R.

Usage:
  run_gcta_greml_one_trait.sh \
    --gcta gcta64 \
    --grm grm_prefix \
    --trait 30000 \
    --input-dir gcta_inputs/traits \
    --threads 8 \
    --out-dir results

Optional:
  --prevalence <K>   # for case-control traits
EOF
}

GCTA_BIN="gcta64"
GRM=""
TRAIT=""
INPUT_DIR="gcta_inputs/traits"
THREADS="8"
OUT_DIR="results"
PREVALENCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gcta) GCTA_BIN="$2"; shift 2 ;;
    --grm) GRM="$2"; shift 2 ;;
    --trait) TRAIT="$2"; shift 2 ;;
    --input-dir) INPUT_DIR="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --prevalence) PREVALENCE="$2"; shift 2 ;;
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

if [[ -z "$GRM" || -z "$TRAIT" ]]; then
  echo "--grm and --trait are required" >&2
  usage
  exit 1
fi

TRAIT_DIR="${INPUT_DIR}/${TRAIT}"
PHENO="${TRAIT_DIR}/${TRAIT}.phen"
COVAR="${TRAIT_DIR}/${TRAIT}.covar"
QCOVAR="${TRAIT_DIR}/${TRAIT}.qcovar"
KEEP="${TRAIT_DIR}/${TRAIT}.keep"

for f in "$PHENO" "$COVAR" "$QCOVAR" "$KEEP"; do
  if [[ ! -s "$f" ]]; then
    echo "Missing required file: $f" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"
OUT_PREFIX="${OUT_DIR}/trait_${TRAIT}"

cmd=(
  "$GCTA_BIN"
  "--reml"
  "--grm" "$GRM"
  "--pheno" "$PHENO"
  "--keep" "$KEEP"
  "--thread-num" "$THREADS"
  "--out" "$OUT_PREFIX"
)

if awk 'NR==1 {exit (NF >= 3 ? 0 : 1)} END {if (NR == 0) exit 1}' "$COVAR"; then
  cmd+=("--covar" "$COVAR")
else
  echo "Notice: skipping --covar because file has <3 columns: $COVAR"
fi

if awk 'NR==1 {exit (NF >= 3 ? 0 : 1)} END {if (NR == 0) exit 1}' "$QCOVAR"; then
  cmd+=("--qcovar" "$QCOVAR")
else
  echo "Notice: skipping --qcovar because file has <3 columns: $QCOVAR"
fi

if [[ -n "$PREVALENCE" ]]; then
  cmd+=("--prevalence" "$PREVALENCE")
fi

echo "Running: ${cmd[*]}"
"${cmd[@]}"
