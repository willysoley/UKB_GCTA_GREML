# UKB RAP GCTA GREML Pipeline (Blood Traits)

This repository prepares and runs SNP-based heritability (GREML) analyses with GCTA for UK Biobank blood traits:

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

It is designed for **UKB RAP / DNANexus** and supports running GCTA via:

- `quay.io/biocontainers/gcta:1.94.1--h9ee0642_0`

## What this repository does

1. Reads sample IDs from PLINK `.fam`.
2. Reads phenotype table (CSV/TSV supported).
3. Reads covariate table (CSV/TSV supported).
4. Builds trait-specific GCTA files (`.phen`, `.covar`, `.qcovar`, `.keep`).
5. Builds GRM once.
6. Runs GREML one trait at a time.
7. Summarizes `.hsq` results.

## Repository structure

- `scripts/prepare_gcta_inputs.R`: prepares per-trait input files.
- `scripts/run_gcta_make_grm.sh`: GRM wrapper.
- `scripts/run_gcta_greml_one_trait.sh`: one-trait GREML wrapper.
- `scripts/run_gcta_greml_all_traits.sh`: loop over traits.
- `scripts/summarize_hsq.py`: parse/summarize `.hsq`.
- `scripts/gcta_docker.sh`: run `gcta64` inside Docker.
- `dnanexus/runbook_swiss_army_knife.md`: RAP execution runbook.
- `traits/blood_trait_codes.txt`: default blood trait list.

## UKB RAP golden rule

- Use **Jupyter/terminal** for lightweight prep, QC, and launching jobs.
- Use **`dx run` jobs** (Swiss Army Knife/workflows) for heavy GRM/GREML compute.
- Keep all data and outputs inside RAP project storage; do not egress protected data.
- Run one trait per job where possible for fault tolerance and easy reruns.

## Find your project ID (`project-...`)

In RAP terminal:

```bash
dx pwd
```

This prints something like `project-ABCDEF1234567890:/your/folder`.
Your project ID is the part before `:`.
When you use `"$PROJECT_ID:/some/path"` with `dx run`, the path is relative to the project root, so you do not include the project name (`disease_proteome`) in the path string.

Convenience command:

```bash
PROJECT_ID=$(dx pwd | sed 's/:.*//')
echo "$PROJECT_ID"
```

Also useful:

```bash
dx env
dx ls
dx find data --name "ukb22418_c1_b0_v2.fam" --path /
```

## Inputs needed

1. Genotype PLINK files (`.bed/.bim/.fam`) as either:
- one merged prefix (`--bfile`), or
- chromosome-split prefixes (`--mbfile`).

2. Phenotype file with participant ID and the target traits.

3. Covariate file with participant ID and covariates.

## Step-by-step

### Step 0: Work in your existing RAP project folder

No download is required if files are already in your project folder.

```bash
dx pwd
ANALYSIS_DIR=/Sool/GCTA_Heritability
REPO_DIR=$ANALYSIS_DIR/UKB_GCTA_Heritability
cd /mnt/project$REPO_DIR
ls -lh
```

### Step 1: Prepare trait-specific files

Recommended for your colleague-style covariate file (`FID/IID`, age/sex/interactions, PCs, batch, center):

```bash
Rscript scripts/prepare_gcta_inputs.R \
  --fam "/mnt/project/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam" \
  --pheno-csv "/mnt/project/Sool/GCTA_Heritability/data/phenotype/raw_blood_phenotypes.csv" \
  --covar-csv "/mnt/project/Sool/covariates_processed_all.tsv" \
  --covar-id-column IID \
  --covar-preset ukb_blood_lab_shared \
  --trait-codes 30000 30010 30020 30040 30050 30060 30080 30120 30130 30140 \
  --num-pcs 20 \
  --outdir gcta_inputs
```

If the genotype/phenotype/covariate files are protected RAP objects that are only available online, do this step through `dx run app-swiss-army-knife` with project paths and `-imount_inputs=true` instead of assuming direct local filesystem access.

Outputs:
- `gcta_inputs/traits/<trait>/<trait>.phen`
- `gcta_inputs/traits/<trait>/<trait>.covar`
- `gcta_inputs/traits/<trait>/<trait>.qcovar`
- `gcta_inputs/traits/<trait>/<trait>.keep`
- `gcta_inputs/trait_manifest.tsv`
- `gcta_inputs/traits_to_run.txt`
- `gcta_inputs/covariate_selection.txt`

### Step 2: Build `mbfile` list (if chromosome split)

Create `genotype_prefixes.mbfile` with one prefix per line (no suffix):

```text
ukb22418_c1_b0_v2
ukb22418_c2_b0_v2
...
ukb22418_c22_b0_v2
```

### Step 3: Pull GCTA Docker image once

```bash
docker pull quay.io/biocontainers/gcta:1.94.1--h9ee0642_0
```

### Step 4: Build GRM

```bash
mkdir -p grm
scripts/gcta_docker.sh \
  --mbfile genotype_prefixes.mbfile \
  --make-grm \
  --thread-num 16 \
  --out grm/blood_grm
```

If you have an unrelated sample list, add:

```bash
--keep unrelated_samples.keep
```

### Step 5: Run GREML one trait at a time

Example `30000`:

```bash
bash scripts/run_gcta_greml_one_trait.sh \
  --gcta "scripts/gcta_docker.sh" \
  --grm grm/blood_grm \
  --trait 30000 \
  --input-dir gcta_inputs/traits \
  --threads 16 \
  --out-dir results
```

Repeat for the remaining traits.

### Step 6: Summarize heritability

```bash
python3 scripts/summarize_hsq.py \
  --results-dir results \
  --out results/hsq_summary.tsv
```

## Covariate presets in `prepare_gcta_inputs.R`

- `--covar-preset auto` (default): simple auto-detect.
- `--covar-preset ukb_greml_common`: age, sex, array/batch, center, genetic PCs.
- `--covar-preset ukb_blood_lab_shared`: tuned for your lab shared file; includes age, sex, age terms/interactions, genetic PCs, rare PCs, array/batch/center, WES/WGS batch when present.

You can always override with explicit `--covar-cols` and `--qcovar-cols`.

## Why these covariates

Common UKB heritability analyses report adjustment for age, sex, array/batch, assessment center, and ancestry PCs, with some models also using age-polynomial and age-by-sex interaction terms.

- Ge et al. (UKB heritability framework): age, sex, array, assessment center, top PCs.
- UKB anthropometric GREML analysis: age, age2, sex, age*sex, age2*sex, center, batch, PCs.
- UKB blood-trait variability analyses: sex, age, technical factors, and genetic PCs are commonly adjusted.

## Notes

- `prepare_gcta_inputs.R` auto-detects delimiter (CSV/TSV).
- `run_gcta_greml_one_trait.sh` skips `--covar` or `--qcovar` if a file has only `FID IID`.
- GREML on large `N` can be memory-heavy; use unrelated subsets and appropriate instance size.
- Using `ukb22418_c1_b0_v2.fam` is just a convenience. For the standard chromosome-split UKB PLINK release, the `.fam` file is effectively the same sample list across chromosomes, so any matching chromosome `.fam` from the same release works.
