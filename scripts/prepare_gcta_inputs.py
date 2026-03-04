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

DELIMITERS = [",", "\t", ";", "|"]


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
        help="Participant ID column name in phenotype CSV (default: participant.eid)",
    )
    parser.add_argument(
        "--pheno-id-column",
        default=None,
        help="Explicit phenotype ID column name (overrides --id-column)",
    )
    parser.add_argument(
        "--covar-id-column",
        default=None,
        help="Covariate ID column name (auto-detected if omitted)",
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
        "--covar-preset",
        choices=["auto", "ukb_greml_common", "ukb_blood_lab_shared"],
        default="auto",
        help=(
            "Covariate selection preset when --covar-cols/--qcovar-cols are omitted: "
            "auto, ukb_greml_common, ukb_blood_lab_shared"
        ),
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


def detect_delimiter(table_path: Path) -> str:
    with table_path.open("r", encoding="utf-8", newline="") as f:
        sample = f.read(8192)
    if not sample:
        return ","
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters="".join(DELIMITERS))
        return dialect.delimiter
    except csv.Error:
        counts = {d: sample.count(d) for d in DELIMITERS}
        best = max(counts, key=counts.get)
        return best if counts[best] > 0 else ","


def read_table_headers(table_path: Path, delimiter: str) -> List[str]:
    with table_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter=delimiter)
        if reader.fieldnames is None:
            raise ValueError(f"Table appears empty: {table_path}")
        return list(reader.fieldnames)


def read_table_as_map(
    table_path: Path,
    id_column: str,
    selected_columns: Sequence[str],
    delimiter: str,
) -> Tuple[List[str], Dict[str, Dict[str, str]]]:
    data: Dict[str, Dict[str, str]] = {}
    with table_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter=delimiter)
        if reader.fieldnames is None:
            raise ValueError(f"Table appears empty: {table_path}")
        headers = list(reader.fieldnames)
        if id_column not in headers:
            raise ValueError(f"ID column '{id_column}' not found in {table_path}")

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


def ordered_unique(cols: Sequence[str]) -> List[str]:
    seen: set[str] = set()
    out: List[str] = []
    for col in cols:
        if col and col not in seen:
            out.append(col)
            seen.add(col)
    return out


def resolve_id_column(headers: Sequence[str], preferred: str | None, fallbacks: Sequence[str]) -> str:
    candidates = []
    if preferred:
        candidates.append(preferred)
    candidates.extend(fallbacks)
    col = first_existing(headers, candidates)
    if not col:
        raise ValueError(
            f"Could not find ID column. Tried: {', '.join(ordered_unique(candidates))}. "
            f"Available columns include: {', '.join(headers[:10])}"
        )
    return col


def find_numbered_columns(headers: Sequence[str], prefixes: Sequence[str], n: int) -> List[str]:
    found: List[str] = []
    for i in range(1, n + 1):
        candidates = [f"{p}{i}" for p in prefixes]
        col = first_existing(headers, candidates)
        if col and col not in found:
            found.append(col)
    return found


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
    sex_col = first_existing(headers, ["participant.p31", "participant.p31_i0", "p31", "sex", "p31_Male"])
    array_col = first_existing(headers, ["Array", "array", "participant.p22000", "participant.p22000_i0", "p22000"])
    center_col = first_existing(headers, ["participant.p54_i0", "participant.p54", "p54_i0", "p54", "assessment_center"])

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

    pcs = find_numbered_columns(
        headers,
        prefixes=[pc_prefix, "participant.p22009_a", "p22009_a", "PC", "pc"],
        n=num_pcs,
    )
    qcovars.extend([pc for pc in pcs if pc not in qcovars])
    return qcovars, age_found


def discover_ukb_greml_common(
    headers: Sequence[str],
    age_col: str,
    pc_prefix: str,
    num_pcs: int,
) -> Tuple[List[str], List[str], str | None]:
    covars: List[str] = []
    qcovars: List[str] = []

    age_found = first_existing(headers, [age_col, "participant.p21022", "participant.p21022_i0", "p21022", "age"])
    sex_binary = first_existing(headers, ["p31_Male", "participant.p31_Male", "sex_male"])
    sex_general = first_existing(headers, ["participant.p31", "participant.p31_i0", "p31", "sex"])

    array = first_existing(headers, ["Array", "array"])
    geno_batch = first_existing(headers, ["participant.p22000", "participant.p22000_i0", "p22000"])
    center = first_existing(headers, ["participant.p54_i0", "participant.p54", "p54_i0", "p54", "assessment_center"])

    covars.extend([array, geno_batch, center])
    if sex_binary:
        qcovars.append(sex_binary)
    elif sex_general:
        covars.append(sex_general)

    if age_found:
        qcovars.append(age_found)

    pcs = find_numbered_columns(
        headers,
        prefixes=[pc_prefix, "participant.p22009_a", "p22009_a"],
        n=num_pcs,
    )
    qcovars.extend(pcs)
    return ordered_unique(covars), ordered_unique(qcovars), age_found


def discover_ukb_blood_lab_shared(
    headers: Sequence[str],
    age_col: str,
    pc_prefix: str,
    num_pcs: int,
) -> Tuple[List[str], List[str], str | None]:
    covars: List[str] = []
    qcovars: List[str] = []

    age_found = first_existing(headers, [age_col, "participant.p21022", "participant.p21022_i0", "p21022", "age"])
    age_sq = first_existing(headers, ["p21022_squared", "participant.p21022_squared", "age_squared", "age2"])
    age_by_sex = first_existing(
        headers,
        ["p21022_by_p31_Male", "participant.p21022_by_p31_Male", "age_by_sex", "age_sex"],
    )
    age2_by_sex = first_existing(
        headers,
        [
            "p21022squared_by_p31_Male",
            "participant.p21022squared_by_p31_Male",
            "age_squared_by_sex",
            "age2_by_sex",
        ],
    )
    sex_binary = first_existing(headers, ["p31_Male", "participant.p31_Male", "sex_male"])
    sex_general = first_existing(headers, ["participant.p31", "participant.p31_i0", "p31", "sex"])

    array = first_existing(headers, ["Array", "array"])
    geno_batch = first_existing(headers, ["participant.p22000", "participant.p22000_i0", "p22000"])
    center = first_existing(headers, ["participant.p54_i0", "participant.p54", "p54_i0", "p54", "assessment_center"])
    wes_batch = first_existing(headers, ["participant.p32050", "p32050"])
    wgs_batch = first_existing(headers, ["participant.p32053", "p32053"])
    covars.extend([array, geno_batch, center, wes_batch, wgs_batch])

    if sex_binary:
        qcovars.append(sex_binary)
    elif sex_general:
        covars.append(sex_general)

    qcovars.extend([age_found, age_sq, age_by_sex, age2_by_sex])

    ancestry_pcs = find_numbered_columns(
        headers,
        prefixes=[pc_prefix, "participant.p22009_a", "p22009_a"],
        n=num_pcs,
    )
    rare_pcs = find_numbered_columns(headers, prefixes=["PC", "pc"], n=num_pcs)
    qcovars.extend(ancestry_pcs + rare_pcs)
    return ordered_unique(covars), ordered_unique(qcovars), age_found


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
    pheno_id_preferred = args.pheno_id_column or args.id_column

    pheno_delim = detect_delimiter(pheno_csv)
    covar_delim = detect_delimiter(covar_csv)

    # Read phenotype headers first for trait discovery
    pheno_headers = read_table_headers(pheno_csv, pheno_delim)
    pheno_id_col = resolve_id_column(
        pheno_headers,
        pheno_id_preferred,
        fallbacks=["participant.eid", "eid", "IID", "FID"],
    )

    trait_map = discover_trait_columns(pheno_headers, args.trait_codes, args.trait_column_template)
    missing_traits = [t for t in args.trait_codes if t not in trait_map]

    # Decide covariate columns using covariate CSV headers.
    covar_headers = read_table_headers(covar_csv, covar_delim)
    covar_id_col = resolve_id_column(
        covar_headers,
        args.covar_id_column,
        fallbacks=[pheno_id_col, args.id_column, "participant.eid", "eid", "IID", "FID"],
    )

    if args.covar_cols is None and args.qcovar_cols is None:
        if args.covar_preset == "ukb_greml_common":
            covar_cols, qcovar_cols, age_col_found = discover_ukb_greml_common(
                covar_headers,
                args.age_col,
                args.pc_prefix,
                args.num_pcs,
            )
        elif args.covar_preset == "ukb_blood_lab_shared":
            covar_cols, qcovar_cols, age_col_found = discover_ukb_blood_lab_shared(
                covar_headers,
                args.age_col,
                args.pc_prefix,
                args.num_pcs,
            )
        else:
            covar_cols = discover_default_covar_cols(covar_headers)
            qcovar_cols, age_col_found = discover_default_qcovar_cols(
                covar_headers,
                args.age_col,
                args.pc_prefix,
                args.num_pcs,
            )
    elif args.covar_cols is None:
        covar_cols = discover_default_covar_cols(covar_headers)
    else:
        covar_cols = [c for c in args.covar_cols if c in set(covar_headers)]

    if args.covar_cols is not None and args.qcovar_cols is None:
        qcovar_cols, age_col_found = discover_default_qcovar_cols(
            covar_headers,
            args.age_col,
            args.pc_prefix,
            args.num_pcs,
        )
    elif args.qcovar_cols is not None:
        qcovar_cols = [c for c in args.qcovar_cols if c in set(covar_headers)]
        age_col_found = first_existing(
            qcovar_cols,
            [args.age_col, "participant.p21022", "participant.p21022_i0", "p21022", "age"],
        )

    covar_cols = ordered_unique(covar_cols)
    qcovar_cols = ordered_unique(qcovar_cols)

    selected_pheno_cols = ordered_unique([pheno_id_col] + list(trait_map.values()))
    selected_covar_cols = ordered_unique([covar_id_col] + covar_cols + qcovar_cols)

    _, pheno_data = read_table_as_map(
        pheno_csv,
        pheno_id_col,
        selected_pheno_cols,
        delimiter=pheno_delim,
    )
    _, covar_data = read_table_as_map(
        covar_csv,
        covar_id_col,
        selected_covar_cols,
        delimiter=covar_delim,
    )

    ensure_dir(outdir)
    traits_root = outdir / "traits"
    ensure_dir(traits_root)

    selected_covars_path = outdir / "covariate_selection.txt"
    with selected_covars_path.open("w", encoding="utf-8") as sf:
        sf.write(f"pheno_file\t{pheno_csv}\n")
        sf.write(f"covar_file\t{covar_csv}\n")
        sf.write(f"pheno_delimiter\t{repr(pheno_delim)}\n")
        sf.write(f"covar_delimiter\t{repr(covar_delim)}\n")
        sf.write(f"pheno_id_column\t{pheno_id_col}\n")
        sf.write(f"covar_id_column\t{covar_id_col}\n")
        sf.write(f"covar_preset\t{args.covar_preset}\n")
        sf.write("covar_columns\t" + ",".join(covar_cols) + "\n")
        sf.write("qcovar_columns\t" + ",".join(qcovar_cols) + "\n")

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
    print(f"Wrote covariate selection: {selected_covars_path}")
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
