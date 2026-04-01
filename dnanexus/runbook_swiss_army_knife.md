# UKB RAP Runbook (Swiss Army Knife + GCTA Docker)

This runbook assumes:
- You are on UKB RAP (RStudio, JupyterLab terminal, or SSH app session).
- `dx` CLI is configured.
- Data files already live inside your RAP project folder.
- Analysis stays inside RAP project storage (no egress).
- Some protected files may only be accessible as online RAP project objects, so the safest path is to submit jobs with `-iin` and `-imount_inputs=true`.

## Step 0: Confirm project context and working folder

```bash
dx pwd
dx env
```

`dx pwd` returns `project-...:/path`. The project ID is the part before `:`.

When you pass files to `dx run` as `"$PROJECT_ID:/some/path"`, the path is relative to the project root, so you do not include the project name (`disease_proteome`) in that string.

Store it in a shell variable:

```bash
PROJECT_ID=$(dx pwd | sed 's/:.*//')
echo "$PROJECT_ID"
```

Set your analysis and repo folders once:

```bash
ANALYSIS_DIR=/Sool/GCTA_Heritability
REPO_DIR=$ANALYSIS_DIR/UKB_GCTA_Heritability
```

Move into the cloned repo inside your analysis folder, then confirm:

```bash
cd /mnt/project$REPO_DIR
ls -lh
```

If you need to discover file locations inside the current project:

```bash
dx ls
dx find data --name "ukb22418_c1_b0_v2.fam" --path /
dx find data --name "raw_blood_phenotypes.csv" --path /
dx find data --name "covariates_processed_all.tsv" --path /
```

## Step 1: Build `mbfile` list for chromosome-split genotypes

Create `genotype_prefixes.mbfile` with one PLINK prefix per line (no suffix):

```text
ukb22418_c1_b0_v2
ukb22418_c2_b0_v2
...
ukb22418_c22_b0_v2
```

## Step 2: Prepare per-trait phenotype/covariate files

From RStudio on RAP, the easiest way to launch Step 1 is:

```bash
Rscript scripts/submit_step1_prepare_dx.R --yes
```

Or from the RStudio console:

```r
system("Rscript scripts/submit_step1_prepare_dx.R --yes")
```

That launcher infers the repo location from your current working directory and submits the Swiss Army Knife job with your protected RAP file paths by default.

If the files are available on the worker filesystem already, you can run this interactively from the repo in your current analysis folder:

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

If the inputs are protected RAP objects that only exist online, use Swiss Army Knife instead of assuming direct local access:

```bash
dx run app-swiss-army-knife \
  -iin="$PROJECT_ID:$REPO_DIR/scripts/prepare_gcta_inputs.R" \
  -iin="$PROJECT_ID:$ANALYSIS_DIR/data/phenotype/raw_blood_phenotypes.csv" \
  -iin="$PROJECT_ID:/Sool/covariates_processed_all.tsv" \
  -iin="$PROJECT_ID:/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam" \
  -icmd="Rscript prepare_gcta_inputs.R --fam ukb22418_c1_b0_v2.fam --pheno-csv raw_blood_phenotypes.csv --covar-csv covariates_processed_all.tsv --covar-id-column IID --covar-preset ukb_blood_lab_shared --trait-codes 30000 30010 30020 30040 30050 30060 30080 30120 30130 30140 --num-pcs 20 --outdir gcta_inputs" \
  -imount_inputs=true \
  --instance-type mem2_ssd1_v2_x16 \
  --destination "$PROJECT_ID:$ANALYSIS_DIR/gcta_runs/prepare" \
  --yes
```

`ukb22418_c1_b0_v2.fam` is used here only as the representative sample list. For the standard chromosome-split UKB release, the `.fam` files are typically the same across chromosomes within the same release, so `c1` is just a convenient example rather than a chromosome-specific requirement.

If you want a leaner model (age/sex + array/batch + center + genetic PCs), switch to:

```bash
--covar-preset ukb_greml_common
```

Key outputs:
- `gcta_inputs/traits/<trait>/<trait>.phen`
- `gcta_inputs/traits/<trait>/<trait>.covar`
- `gcta_inputs/traits/<trait>/<trait>.qcovar`
- `gcta_inputs/traits/<trait>/<trait>.keep`
- `gcta_inputs/trait_manifest.tsv`
- `gcta_inputs/traits_to_run.txt`
- `gcta_inputs/covariate_selection.txt`

## Step 3: Pull GCTA Docker once

```bash
docker pull quay.io/biocontainers/gcta:1.94.1--h9ee0642_0
```

## Step 4: Build GRM

```bash
mkdir -p grm
scripts/gcta_docker.sh \
  --mbfile genotype_prefixes.mbfile \
  --make-grm \
  --thread-num 16 \
  --out grm/blood_grm
```

If you have unrelated IDs, add:

```bash
--keep unrelated_samples.keep
```

## Step 5: Run GREML one trait at a time

Example (`30000`):

```bash
bash scripts/run_gcta_greml_one_trait.sh \
  --gcta "scripts/gcta_docker.sh" \
  --grm grm/blood_grm \
  --trait 30000 \
  --input-dir gcta_inputs/traits \
  --threads 16 \
  --out-dir results
```

Repeat for all trait codes.

## Step 6: Summarize heritability estimates

```bash
python3 scripts/summarize_hsq.py \
  --results-dir results \
  --out results/hsq_summary.tsv
```

## Optional: run as Swiss Army Knife jobs (`dx run`)

Use jobs for long runs (recommended over keeping notebook kernels alive).

Prepare job example:

```bash
ANALYSIS_DIR=/Sool/GCTA_Heritability
REPO_DIR=$ANALYSIS_DIR/UKB_GCTA_Heritability

dx run app-swiss-army-knife \
  -iin="$PROJECT_ID:$REPO_DIR/scripts/prepare_gcta_inputs.R" \
  -iin="$PROJECT_ID:$ANALYSIS_DIR/data/phenotype/raw_blood_phenotypes.csv" \
  -iin="$PROJECT_ID:/Sool/covariates_processed_all.tsv" \
  -iin="$PROJECT_ID:/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam" \
  -icmd="Rscript prepare_gcta_inputs.R --fam ukb22418_c1_b0_v2.fam --pheno-csv raw_blood_phenotypes.csv --covar-csv covariates_processed_all.tsv --covar-id-column IID --covar-preset ukb_blood_lab_shared --num-pcs 20 --outdir gcta_inputs" \
  -imount_inputs=true \
  --instance-type mem2_ssd1_v2_x16 \
  --destination "$PROJECT_ID:$ANALYSIS_DIR/gcta_runs/prepare" \
  --yes
```

Use the same pattern for GRM and GREML jobs (attach required files with `-iin`, update `-icmd`).

## Operational guidance (UKB RAP)

- Use Jupyter notebook/terminal for setup, QC checks, and job submission.
- Use `dx run` jobs for compute-heavy steps (GRM, GREML).
- Keep one trait per job for easier reruns and logs.
- Pin container image versions and keep all `.log` and `.hsq` outputs.
