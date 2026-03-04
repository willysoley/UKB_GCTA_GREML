#!/usr/bin/env python3
"""Prepare trait-specific GCTA GREML input files from UKB RAP exports.

This script joins:
1) PLINK FAM IDs (FID/IID)
2) phenotype CSV (e.g., table-exporter output)
3) covariate CSV (optional, defaults to phenotype CSV)

Outputs per trait:
- <trait>.phen   (FID IID PHENO)
- <trait>.covar  (FID IID + categorical covariates)
- <trait>.qcovar (FID IID + quantitative covariates)
- <trait>.keep   (FID IID)

And one manifest file with per-trait sample counts.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


DEFAULT_TRAITS = [
    "30000",
    "30010",
    "30020",
    "30040",
    "30050",
    "30060",
    "30080",
    "30120",
    "30130",
    "30140",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare GCTA input files for UKB traits")
    parser.add_argument("--fam", required=True, help="Path to PLINK .fam file")
    parser.add_argument("--pheno-csv", required=True, help="Phenotype CSV path")
    parser.add_argument(
        "--covar-csv",
        default=None,
        help="Covariate CSV path (default: same as --pheno-csv)",
    )
    parser.add_argument(
        "--outdir",
        default="gcta_inputs",
        help="Output directory (default: gcta_inputs)",
    )
    parser.add_argument(
        "--trait-codes",
        nargs="*",
        default=DEFAULT_TRAITS,
        help="Trait codes to process (default: blood panel in repo)",
    )
    parser.add_argument(
        "--trait-column-template",
        default="participant.p{code}_i0",
        help="Trait column template (default: participant.p{code}_i0)",
    )
    parser.add_argument(
        "--id-column",
        default="participant.eid",
        help="Participant ID column name in CSV files (default: participant.eid)",
    )
    parser.add_argument(
        "--fam-id-column",
        choices=["IID", "FID"],
        default="IID",
        help="Which FAM column to match against participant.eid (default: IID)",
    )
    parser.add_argument(
        "--covar-cols",
        nargs="*",
        default=None,
        help="Categorical covariate columns. If omitted, auto-detects UKB sex/array/center columns if present.",
    )
    parser.add_argument(
        "--qcovar-cols",
        nargs="*",
        default=None,
        help="Quantitative covariate columns. If omitted, auto-detects age + PCs if present.",
    )
    parser.add_argument(
        "--age-col",
        default="participant.p21022",
        help="Age column for qcovar and age^2 (default: participant.p21022)",
    )
    parser.add_argument(
        "--pc-prefix",
        default="participant.p22009_a",
        help="PC prefix used to auto-discover PCs (default: participant.p22009_a)",
    )
    parser.add_argument(
        "--num-pcs",
        type=int,
        default=20,
        help="Number of PCs to include when auto-detecting (default: 20)",
    )
    parser.add_argument(
        "--add-age-squared",
        action="store_true",
        help="Add age^2 as qcovar column when age is available",
    )
    parser.add_argument(
        "--missing-values",
        nargs="*",
        default=["", "NA", "NaN", "nan", "NULL", "null", "-9"],
        help="Tokens treated as missing",
    )
    return parser.parse_args()


def normalize_id(value: str) -> str:
    if value is None:
        return ""
    s = value.strip()
    if s == "":
        return ""
    if re.fullmatch(r"\d+\.0", s):
        return s[:-2]
    return s


def is_missing(value: str, missing_tokens: set[str]) -> bool:
    if value is None:
        return True
    return value.strip() in missing_tokens


def read_fam(fam_path: Path) -> List[Tuple[str, str]]:
    fam_rows: List[Tuple[str, str]] = []
    with fam_path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 2:
                raise ValueError(f"Malformed FAM line {line_no}: expected >=2 columns")
            fam_rows.append((parts[0], parts[1]))
    if not fam_rows:
        raise ValueError("No samples found in FAM file")
    return fam_rows


def read_csv_as_map(
    csv_path: Path,
    id_column: str,
    selected_columns: Sequence[str],
) -> Tuple[List[str], Dict[str, Dict[str, str]]]:
    data: Dict[str, Dict[str, str]] = {}
    with csv_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise ValueError(f"CSV appears empty: {csv_path}")
        headers = list(reader.fieldnames)
        if id_column not in headers:
            raise ValueError(f"ID column '{id_column}' not found in {csv_path}")

        needed = [c for c in selected_columns if c in headers]
        for row in reader:
            pid = normalize_id(row.get(id_column, ""))
            if not pid:
                continue
            if pid in data:
                continue
            slim = {c: row.get(c, "") for c in needed}
            data[pid] = slim
    return headers, data


def first_existing(headers: Sequence[str], candidates: Iterable[str]) -> str | None:
    header_set = set(headers)
    for c in candidates:
        if c in header_set:
            return c
    return None


def discover_trait_columns(
    headers: Sequence[str],
    trait_codes: Sequence[str],
    template: str,
) -> Dict[str, str]:
    mapping: Dict[str, str] = {}
    for code in trait_codes:
        candidates = [
            template.format(code=code),
            f"participant.p{code}_i0",
            f"p{code}_i0",
            f"participant.p{code}",
            code,
        ]
        col = first_existing(headers, candidates)
        if col:
            mapping[code] = col
    return mapping


def discover_default_covar_cols(headers: Sequence[str]) -> List[str]:
    discovered: List[str] = []
    sex_col = first_existing(headers, ["participant.p31", "participant.p31_i0", "p31", "sex"])
    array_col = first_existing(headers, ["participant.p22000", "participant.p22000_i0", "p22000", "array"])
    center_col = first_existing(headers, ["participant.p54_i0", "participant.p54", "p54_i0", "assessment_center"])

    for c in [sex_col, array_col, center_col]:
        if c and c not in discovered:
            discovered.append(c)
    return discovered


def discover_default_qcovar_cols(
    headers: Sequence[str],
    age_col: str,
    pc_prefix: str,
    num_pcs: int,
) -> Tuple[List[str], str | None]:
    qcovars: List[str] = []

    age_found = first_existing(headers, [age_col, "participant.p21022", "participant.p21022_i0", "p21022", "age"])
    if age_found:
        qcovars.append(age_found)

    for i in range(1, num_pcs + 1):
        candidates = [
            f"{pc_prefix}{i}",
            f"participant.p22009_a{i}",
            f"p22009_a{i}",
            f"PC{i}",
            f"pc{i}",
        ]
        col = first_existing(headers, candidates)
        if col and col not in qcovars:
            qcovars.append(col)
    return qcovars, age_found


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


@dataclass
class TraitSummary:
    trait: str
    trait_column: str
    n_analyzed: int
    dropped_missing_pheno: int
    dropped_missing_covars: int


def format_row(values: Sequence[str]) -> str:
    return "\t".join(values) + "\n"


def main() -> int:
    args = parse_args()

    fam_path = Path(args.fam)
    pheno_csv = Path(args.pheno_csv)
    covar_csv = Path(args.covar_csv) if args.covar_csv else pheno_csv
    outdir = Path(args.outdir)

    missing_tokens = set(args.missing_values)

    fam_rows = read_fam(fam_path)

    # Read phenotype headers first for trait discovery
    with pheno_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise ValueError("Phenotype CSV is empty")
        pheno_headers = list(reader.fieldnames)

    trait_map = discover_trait_columns(pheno_headers, args.trait_codes, args.trait_column_template)
    missing_traits = [t for t in args.trait_codes if t not in trait_map]

    # Decide covariate columns using covariate CSV headers.
    with covar_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            raise ValueError("Covariate CSV is empty")
        covar_headers = list(reader.fieldnames)

    if args.covar_cols is None:
        covar_cols = discover_default_covar_cols(covar_headers)
    else:
        covar_cols = [c for c in args.covar_cols if c in covar_headers]

    if args.qcovar_cols is None:
        qcovar_cols, age_col_found = discover_default_qcovar_cols(
            covar_headers,
            args.age_col,
            args.pc_prefix,
            args.num_pcs,
        )
    else:
        qcovar_cols = [c for c in args.qcovar_cols if c in covar_headers]
        age_col_found = args.age_col if args.age_col in qcovar_cols else None

    selected_pheno_cols = [args.id_column] + list(trait_map.values())
    selected_covar_cols = [args.id_column] + covar_cols + qcovar_cols

    _, pheno_data = read_csv_as_map(pheno_csv, args.id_column, selected_pheno_cols)
    _, covar_data = read_csv_as_map(covar_csv, args.id_column, selected_covar_cols)

    ensure_dir(outdir)
    traits_root = outdir / "traits"
    ensure_dir(traits_root)

    manifest_path = outdir / "trait_manifest.tsv"
    summary: List[TraitSummary] = []

    for trait in args.trait_codes:
        if trait not in trait_map:
            continue

        trait_col = trait_map[trait]
        trait_dir = traits_root / trait
        ensure_dir(trait_dir)

        phen_path = trait_dir / f"{trait}.phen"
        covar_path = trait_dir / f"{trait}.covar"
        qcovar_path = trait_dir / f"{trait}.qcovar"
        keep_path = trait_dir / f"{trait}.keep"

        n_analyzed = 0
        dropped_missing_pheno = 0
        dropped_missing_covars = 0

        with (
            phen_path.open("w", encoding="utf-8") as phen_f,
            covar_path.open("w", encoding="utf-8") as covar_f,
            qcovar_path.open("w", encoding="utf-8") as qcovar_f,
            keep_path.open("w", encoding="utf-8") as keep_f,
        ):
            for fid, iid in fam_rows:
                sample_id = iid if args.fam_id_column == "IID" else fid

                pvals = pheno_data.get(sample_id)
                if not pvals:
                    continue

                y = pvals.get(trait_col, "")
                if is_missing(y, missing_tokens):
                    dropped_missing_pheno += 1
                    continue

                cvals = covar_data.get(sample_id)
                if cvals is None:
                    dropped_missing_covars += 1
                    continue

                covar_values = [cvals.get(c, "") for c in covar_cols]
                qcovar_values = [cvals.get(c, "") for c in qcovar_cols]

                if any(is_missing(v, missing_tokens) for v in covar_values + qcovar_values):
                    dropped_missing_covars += 1
                    continue

                age_sq_value = None
                if args.add_age_squared and age_col_found:
                    try:
                        age_val = float(cvals.get(age_col_found, ""))
                        age_sq_value = f"{age_val * age_val:.8f}"
                    except ValueError:
                        dropped_missing_covars += 1
                        continue

                phen_f.write(format_row([fid, iid, y]))
                covar_f.write(format_row([fid, iid] + covar_values))

                qrow = [fid, iid] + qcovar_values
                if age_sq_value is not None:
                    qrow.append(age_sq_value)
                qcovar_f.write(format_row(qrow))

                keep_f.write(format_row([fid, iid]))
                n_analyzed += 1

        summary.append(
            TraitSummary(
                trait=trait,
                trait_column=trait_col,
                n_analyzed=n_analyzed,
                dropped_missing_pheno=dropped_missing_pheno,
                dropped_missing_covars=dropped_missing_covars,
            )
        )

    with manifest_path.open("w", encoding="utf-8") as mf:
        mf.write("trait\ttrait_column\tn_analyzed\tdropped_missing_pheno\tdropped_missing_covars\n")
        for item in summary:
            mf.write(
                f"{item.trait}\t{item.trait_column}\t{item.n_analyzed}\t"
                f"{item.dropped_missing_pheno}\t{item.dropped_missing_covars}\n"
            )

    trait_list_path = outdir / "traits_to_run.txt"
    with trait_list_path.open("w", encoding="utf-8") as tf:
        for item in summary:
            if item.n_analyzed > 0:
                tf.write(f"{item.trait}\n")

    print(f"Wrote manifest: {manifest_path}")
    print(f"Wrote trait list: {trait_list_path}")
    print(f"Prepared traits with data: {sum(1 for s in summary if s.n_analyzed > 0)} / {len(args.trait_codes)}")

    if missing_traits:
        print("Warning: trait codes not found in phenotype CSV columns:", ", ".join(missing_traits), file=sys.stderr)

    empty_traits = [s.trait for s in summary if s.n_analyzed == 0]
    if empty_traits:
        print("Warning: no analyzable rows after filtering for traits:", ", ".join(empty_traits), file=sys.stderr)

    if not covar_cols:
        print("Warning: no categorical covariates selected.", file=sys.stderr)
    if not qcovar_cols and not (args.add_age_squared and age_col_found):
        print("Warning: no quantitative covariates selected.", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
