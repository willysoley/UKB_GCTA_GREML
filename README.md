# UKB RAP GCTA GREML Pipeline (Blood Traits)

This repository prepares and runs SNP-based heritability (GREML) analyses with GCTA for the following UK Biobank blood phenotype codes:

- `30000`
- `30010`
- `30020`
- `30040`
- `30050`
- `30060`
- `30080`
- `30120`
- `30130`
- `30140`

It is designed for **UKB RAP / DNANexus** workflows, including running GCTA via the Docker image:

- `quay.io/biocontainers/gcta:1.94.1--h9ee0642_0`

## What this repository does

1. Takes UKB genotype sample IDs from a `.fam` file.
2. Takes a phenotype CSV (your blood traits file).
3. Takes a covariate CSV.
4. Creates trait-specific GCTA inputs (`.phen`, `.covar`, `.qcovar`, `.keep`) for each trait.
5. Builds a GRM once.
6. Runs GREML per trait one-by-one.
7. Summarizes `.hsq` outputs into one table.

## Repository structure

- `scripts/prepare_gcta_inputs.py`: creates per-trait GCTA input files.
- `scripts/run_gcta_make_grm.sh`: wrapper for GRM generation.
- `scripts/run_gcta_greml_one_trait.sh`: runs one GREML trait.
- `scripts/run_gcta_greml_all_traits.sh`: loops over all prepared traits.
- `scripts/summarize_hsq.py`: aggregates all `.hsq` outputs.
- `scripts/gcta_docker.sh`: runs `gcta64` inside Docker (RAP-friendly).
- `traits/blood_trait_codes.txt`: trait list.
- `dnanexus/runbook_swiss_army_knife.md`: RAP runbook and `dx run` examples.
- `examples/genotype_prefixes.mbfile`: template for chromosome-split genotype prefixes.

## Inputs you need

1. Genotype PLINK files (`.bed`, `.bim`, `.fam`) either:
- Single merged prefix (`--bfile`), or
- One prefix per chromosome using `--mbfile`.

2. Phenotype CSV containing:
- `participant.eid`
- trait columns (default expected format: `participant.p<code>_i0`)

3. Covariate CSV containing at least participant ID plus covariates.

## Step-by-step (one-by-one)

### Step 1: Prepare trait-specific files

```bash
python3 scripts/prepare_gcta_inputs.py \
  --fam ukb22418_c1_b0_v2.fam \
  --pheno-csv raw_blood_phenotypes.csv \
  --covar-csv covariates.csv \
  --trait-codes 30000 30010 30020 30040 30050 30060 30080 30120 30130 30140 \
  --id-column participant.eid \
  --add-age-squared \
  --outdir gcta_inputs
```

Outputs are written to:
- `gcta_inputs/traits/<trait>/<trait>.phen`
- `gcta_inputs/traits/<trait>/<trait>.covar`
- `gcta_inputs/traits/<trait>/<trait>.qcovar`
- `gcta_inputs/traits/<trait>/<trait>.keep`
- `gcta_inputs/trait_manifest.tsv`
- `gcta_inputs/traits_to_run.txt`

If your covariate column names differ, pass them explicitly, for example:

```bash
python3 scripts/prepare_gcta_inputs.py \
  --fam ukb22418_c1_b0_v2.fam \
  --pheno-csv raw_blood_phenotypes.csv \
  --covar-csv covariates.csv \
  --covar-cols participant.p31 participant.p22000 participant.p54_i0 \
  --qcovar-cols participant.p21022 participant.p22009_a1 participant.p22009_a2 \
  --outdir gcta_inputs
```

### Step 2: Build genotype prefix list for GRM (`--mbfile`)

Create `genotype_prefixes.mbfile` with one PLINK prefix per line (no suffix):

```text
ukb22418_c1_b0_v2
ukb22418_c2_b0_v2
...
ukb22418_c22_b0_v2
```

### Step 3: Build GRM once

Option A: through Docker wrapper:

```bash
mkdir -p grm
scripts/gcta_docker.sh \
  --mbfile genotype_prefixes.mbfile \
  --make-grm \
  --thread-num 16 \
  --out grm/blood_grm
```

Option B: native `gcta64` on PATH:

```bash
bash scripts/run_gcta_make_grm.sh \
  --gcta gcta64 \
  --mbfile genotype_prefixes.mbfile \
  --threads 16 \
  --out grm/blood_grm
```

If you have an unrelated-sample keep list, add `--keep unrelated_samples.keep` in GRM creation.

### Step 4: Run GREML one trait at a time

Example for trait `30000`:

```bash
bash scripts/run_gcta_greml_one_trait.sh \
  --gcta "scripts/gcta_docker.sh" \
  --grm grm/blood_grm \
  --trait 30000 \
  --input-dir gcta_inputs/traits \
  --threads 16 \
  --out-dir results
```

`run_gcta_greml_one_trait.sh` automatically skips `--covar` or `--qcovar` if the prepared file only has `FID IID` columns.

Then repeat for each trait:
- `30010`, `30020`, `30040`, `30050`, `30060`, `30080`, `30120`, `30130`, `30140`

### Step 5: Optional batch run (still one-trait-per-job inside loop)

```bash
bash scripts/run_gcta_greml_all_traits.sh \
  --gcta "scripts/gcta_docker.sh" \
  --grm grm/blood_grm \
  --traits-file gcta_inputs/traits_to_run.txt \
  --input-dir gcta_inputs/traits \
  --threads 16 \
  --out-dir results
```

### Step 6: Summarize output

```bash
python3 scripts/summarize_hsq.py \
  --results-dir results \
  --out results/hsq_summary.tsv
```

## DNANexus / RAP-specific notes

- Your Swiss Army Knife log confirms Docker pull/run works for this GCTA image.
- For managed jobs, use `dx run app-swiss-army-knife` and pass script/data files with `-iin` and commands with `-icmd`.
- A complete RAP runbook with examples is in:
  - `dnanexus/runbook_swiss_army_knife.md`

## Common pitfalls

- ID mismatch between `participant.eid` and `.fam` IID/FID -> results in empty trait files.
- Missing covariates -> large sample drop after filtering.
- GREML memory pressure on very large `N` -> use stricter sample filtering (`--keep`) before GRM.
- Wrong phenotype column names -> pass explicit trait or covariate columns.

## Reproducibility

Keep these with each run:
- exact command lines used
- GCTA version/image digest
- `gcta_inputs/trait_manifest.tsv`
- all `.log` and `.hsq` files
