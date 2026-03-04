#!/usr/bin/env python3
"""Summarize GCTA .hsq files into one TSV."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--results-dir", required=True, help="Directory with trait_*.hsq files")
    p.add_argument("--out", default="hsq_summary.tsv", help="Output TSV")
    return p.parse_args()


def parse_hsq(path: Path) -> dict[str, str]:
    out = {
        "V(G)": "",
        "V(G)_SE": "",
        "V(e)": "",
        "V(e)_SE": "",
        "Vp": "",
        "Vp_SE": "",
        "h2": "",
        "h2_SE": "",
        "logL": "",
        "logL0": "",
        "LRT": "",
        "LRT_P": "",
        "n": "",
    }

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            key = parts[0]
            if key == "V(G)":
                out["V(G)"] = parts[1]
                out["V(G)_SE"] = parts[2] if len(parts) > 2 else ""
            elif key == "V(e)":
                out["V(e)"] = parts[1]
                out["V(e)_SE"] = parts[2] if len(parts) > 2 else ""
            elif key == "Vp":
                out["Vp"] = parts[1]
                out["Vp_SE"] = parts[2] if len(parts) > 2 else ""
            elif key == "V(G)/Vp":
                out["h2"] = parts[1]
                out["h2_SE"] = parts[2] if len(parts) > 2 else ""
            elif key == "logL":
                out["logL"] = parts[1]
            elif key == "logL0":
                out["logL0"] = parts[1]
            elif key == "LRT":
                out["LRT"] = parts[1]
            elif key == "Pval":
                out["LRT_P"] = parts[1]
            elif key == "n":
                out["n"] = parts[1]
    return out


def main() -> int:
    args = parse_args()
    results_dir = Path(args.results_dir)
    hsq_files = sorted(results_dir.glob("trait_*.hsq"))

    header = [
        "trait",
        "n",
        "h2",
        "h2_SE",
        "V(G)",
        "V(G)_SE",
        "V(e)",
        "V(e)_SE",
        "Vp",
        "Vp_SE",
        "LRT",
        "LRT_P",
        "logL",
        "logL0",
    ]

    out_path = Path(args.out)
    with out_path.open("w", encoding="utf-8") as out:
        out.write("\t".join(header) + "\n")
        for f in hsq_files:
            trait = f.stem.replace("trait_", "")
            vals = parse_hsq(f)
            row = [trait] + [vals.get(c, "") for c in header[1:]]
            out.write("\t".join(row) + "\n")

    print(f"Wrote {out_path} with {len(hsq_files)} traits")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
