# UKB RAP Runbook (Swiss Army Knife + GCTA Docker)

This runbook assumes:
- You are in a RAP terminal/Jupyter session with `dx` CLI authenticated.
- You cloned this repository in RAP.
- Your PLINK data are available as UKB genotype files (`.bed/.bim/.fam`).
- You have `raw_blood_phenotypes.csv` and a covariate CSV.

## Step 0: Stage files in one working folder

In RAP terminal:

```bash
mkdir -p work && cd work
```

Download required files (replace paths with your project paths):

```bash
dx download 'project-XXXX:/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam'
dx download 'project-XXXX:/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.bed'
dx download 'project-XXXX:/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.bim'

# Repeat download for c2..c22 bed/bim/fam if using chromosome-split files.

dx download 'project-XXXX:/path/to/raw_blood_phenotypes.csv'
dx download 'project-XXXX:/path/to/covariates.csv'
```

Copy repository scripts into this folder or run from repository root and point paths accordingly.

## Step 1: Build `mbfile` list for multi-chromosome GRM

Create `genotype_prefixes.mbfile` with one prefix per line (no suffix):

```text
ukb22418_c1_b0_v2
ukb22418_c2_b0_v2
...
ukb22418_c22_b0_v2
```

## Step 2: Prepare per-trait phenotype/covariate files

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

Output:
- `gcta_inputs/traits/<trait>/<trait>.phen`
- `gcta_inputs/traits/<trait>/<trait>.covar`
- `gcta_inputs/traits/<trait>/<trait>.qcovar`
- `gcta_inputs/traits/<trait>/<trait>.keep`
- `gcta_inputs/trait_manifest.tsv`
- `gcta_inputs/traits_to_run.txt`

## Step 3: Pull GCTA Docker once (Swiss Army Knife style)

```bash
docker pull quay.io/biocontainers/gcta:1.94.1--h9ee0642_0
```

## Step 4: Build GRM

If using Docker wrapper:

```bash
mkdir -p grm
scripts/gcta_docker.sh --help
```

Then:

```bash
scripts/gcta_docker.sh \
  --mbfile genotype_prefixes.mbfile \
  --make-grm \
  --thread-num 16 \
  --out grm/blood_grm
```

If you already have an unrelated-sample keep file, add:

```bash
--keep unrelated_samples.keep
```

Alternative (native if `gcta64` is on PATH):

```bash
bash scripts/run_gcta_make_grm.sh \
  --gcta gcta64 \
  --mbfile genotype_prefixes.mbfile \
  --threads 16 \
  --out grm/blood_grm
```

## Step 5: Run GREML one trait at a time

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

Repeat for each trait code.

## Step 6: Or run all traits in a loop

```bash
bash scripts/run_gcta_greml_all_traits.sh \
  --gcta "scripts/gcta_docker.sh" \
  --grm grm/blood_grm \
  --traits-file gcta_inputs/traits_to_run.txt \
  --input-dir gcta_inputs/traits \
  --threads 16 \
  --out-dir results
```

## Step 7: Summarize heritability estimates

```bash
python3 scripts/summarize_hsq.py \
  --results-dir results \
  --out results/hsq_summary.tsv
```

## Optional: submit as a Swiss Army Knife job via `dx run`

From RAP terminal, you can submit commands as jobs instead of running interactively:

```bash
dx run app-swiss-army-knife \
  -iin="project-XXXX:/path/to/repo/scripts/prepare_gcta_inputs.py" \
  -iin="project-XXXX:/path/to/raw_blood_phenotypes.csv" \
  -iin="project-XXXX:/path/to/covariates.csv" \
  -iin="project-XXXX:/path/to/ukb22418_c1_b0_v2.fam" \
  -icmd="python3 prepare_gcta_inputs.py --fam ukb22418_c1_b0_v2.fam --pheno-csv raw_blood_phenotypes.csv --covar-csv covariates.csv --add-age-squared --outdir gcta_inputs" \
  --instance-type mem2_ssd1_v2_x16 \
  --destination "project-XXXX:/gcta_runs/prepare" \
  --yes
```

Use the same pattern for GRM and GREML jobs by adding required files with `-iin` and updating `-icmd`.

## Notes
- GREML on very large sample sizes can be memory-intensive. Restrict to unrelated individuals with a `--keep` file if needed.
- If your column names differ from defaults, pass explicit `--covar-cols` and `--qcovar-cols` to `prepare_gcta_inputs.py`.
