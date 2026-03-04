#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_gcta_make_grm.sh \
    --gcta gcta64 \
    [--bfile <plink_prefix> | --mbfile <multi_bfile_list.txt>] \
    [--keep sample.keep] \
    [--threads 8] \
    --out grm_prefix

Optional memory-safe split mode:
  --make-grm-part <part_index> <num_parts>
EOF
}

GCTA_BIN="gcta64"
BFILE=""
MBFILE=""
KEEP=""
THREADS="8"
OUT=""
PART_IDX=""
NUM_PARTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gcta) GCTA_BIN="$2"; shift 2 ;;
    --bfile) BFILE="$2"; shift 2 ;;
    --mbfile) MBFILE="$2"; shift 2 ;;
    --keep) KEEP="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --make-grm-part)
      PART_IDX="$2"
      NUM_PARTS="$3"
      shift 3
      ;;
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

if [[ -z "$OUT" ]]; then
  echo "--out is required" >&2
  usage
  exit 1
fi

if [[ -n "$BFILE" && -n "$MBFILE" ]]; then
  echo "Choose only one of --bfile or --mbfile" >&2
  exit 1
fi
if [[ -z "$BFILE" && -z "$MBFILE" ]]; then
  echo "Provide one of --bfile or --mbfile" >&2
  exit 1
fi

cmd=("$GCTA_BIN" "--make-grm" "--thread-num" "$THREADS" "--out" "$OUT")

if [[ -n "$BFILE" ]]; then
  cmd+=("--bfile" "$BFILE")
else
  cmd+=("--mbfile" "$MBFILE")
fi

if [[ -n "$KEEP" ]]; then
  cmd+=("--keep" "$KEEP")
fi

if [[ -n "$PART_IDX" || -n "$NUM_PARTS" ]]; then
  if [[ -z "$PART_IDX" || -z "$NUM_PARTS" ]]; then
    echo "--make-grm-part requires two numbers: <part_index> <num_parts>" >&2
    exit 1
  fi
  cmd+=("--make-grm-part" "$PART_IDX" "$NUM_PARTS")
fi

mkdir -p "$(dirname "$OUT")"

echo "Running: ${cmd[*]}"
"${cmd[@]}"
