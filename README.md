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

- Use **RStudio, Jupyter, or a RAP terminal** for lightweight prep, QC, and launching jobs.
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

### Step 0: Keep data in RAP project storage, but run code from a writable folder

In RAP, `/mnt/project` is usually read-only inside Jupyter/RStudio. The practical pattern is:

- keep protected genotype/phenotype/covariate files in `/mnt/project`
- clone this repo into your home directory
- run local scripts from `~/UKB_GCTA_GREML`
- submit heavy compute with `dx run`

Example:

```bash
dx pwd
cd ~
git clone git@github.com:willysoley/UKB_GCTA_GREML.git
cd ~/UKB_GCTA_GREML
```

### Step 1: Prepare trait-specific files

Recommended for your colleague-style covariate file (`FID/IID`, age/sex/interactions, PCs, batch, center):

This is the exact direct command to run from the RAP terminal or RStudio terminal:

```bash
cd ~/UKB_GCTA_GREML
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

If you want to run the same Step 1 from the RStudio console instead of the terminal:

```r
system(paste(
  "cd ~/UKB_GCTA_GREML &&",
  "Rscript scripts/prepare_gcta_inputs.R",
  "--fam '/mnt/project/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam'",
  "--pheno-csv '/mnt/project/Sool/GCTA_Heritability/data/phenotype/raw_blood_phenotypes.csv'",
  "--covar-csv '/mnt/project/Sool/covariates_processed_all.tsv'",
  "--covar-id-column IID",
  "--covar-preset ukb_blood_lab_shared",
  "--trait-codes 30000 30010 30020 30040 30050 30060 30080 30120 30130 30140",
  "--num-pcs 20",
  "--outdir gcta_inputs"
))
```

This is the Step 1 command we used in practice. It keeps the protected inputs in RAP and writes the prepared outputs under your home directory in `~/UKB_GCTA_GREML/gcta_inputs`.

Outputs:
- `gcta_inputs/traits/<trait>/<trait>.phen`
- `gcta_inputs/traits/<trait>/<trait>.covar`
- `gcta_inputs/traits/<trait>/<trait>.qcovar`
- `gcta_inputs/traits/<trait>/<trait>.keep`
- `gcta_inputs/trait_manifest.tsv`
- `gcta_inputs/traits_to_run.txt`
- `gcta_inputs/covariate_selection.txt`

### Step 2: Check the prepared files

```bash
cd ~/UKB_GCTA_GREML
head gcta_inputs/trait_manifest.tsv
head gcta_inputs/covariate_selection.txt
head gcta_inputs/traits/30000/30000.phen
head gcta_inputs/traits/30000/30000.covar
head gcta_inputs/traits/30000/30000.qcovar
head gcta_inputs/traits/30000/30000.keep
```

### Step 3: Submit the GRM as a separate Swiss Army Knife job

This is the exact terminal block to copy and paste. It uses all 22 chromosome prefixes and submits a standalone GRM job inside RAP.

```bash
PROJECT_ID=$(dx pwd | sed 's/:.*//')
GENO_DIR="/Bulk/Genotype Results/Genotype calls"
DEST="/Sool/Analysis/GCTA_Heritability/20260331_test_run/gcta_runs/grm"

DX_INPUTS=()
for chr in $(seq 1 22); do
  prefix="$GENO_DIR/ukb22418_c${chr}_b0_v2"
  DX_INPUTS+=("-iin=${PROJECT_ID}:${prefix}.bed")
  DX_INPUTS+=("-iin=${PROJECT_ID}:${prefix}.bim")
  DX_INPUTS+=("-iin=${PROJECT_ID}:${prefix}.fam")
done

GCTA_CMD=$(cat <<'EOF'
set -euo pipefail
mkdir -p grm
for chr in $(seq 1 22); do
  echo "ukb22418_c${chr}_b0_v2"
done > genotype_prefixes.mbfile

docker run --rm \
  -u "$(id -u):$(id -g)" \
  -w "$PWD" \
  -v "$PWD":"$PWD" \
  quay.io/biocontainers/gcta:1.94.1--h9ee0642_0 \
  gcta64 \
    --mbfile genotype_prefixes.mbfile \
    --make-grm \
    --thread-num 16 \
    --out grm/blood_grm
EOF
)

dx run app-swiss-army-knife \
  "${DX_INPUTS[@]}" \
  -icmd="$GCTA_CMD" \
  --instance-type mem2_ssd1_v2_x32 \
  --destination "${PROJECT_ID}:${DEST}" \
  --yes
```

Expected outputs:
- `blood_grm.grm.bin`
- `blood_grm.grm.N.bin`
- `blood_grm.grm.id`

If you already have a project-level keep file for unrelated or QC-passed samples, add it both as another `-iin=...` input and in the GCTA command as `--keep your_keep_file.keep`.

Important:
- A full dense GRM on all ~488k UKB samples is usually not practical in a standard RAP job. GCTA may report memory requirements on the order of terabytes.
- For GREML, the usual practical approach is to build the GRM on an unrelated/QC-passed subset using `--keep`.
- If you need the full GRM itself for another purpose, GCTA supports `--make-grm-part` to split GRM construction across many jobs, but GREML on the full dense UKB-scale GRM is still generally impractical.

### Step 3b: Submit a partitioned GRM across many jobs

If you want to build the full dense GRM itself, use GCTA's `--make-grm-part`.

This is the exact terminal block to submit 250 part-jobs, following the pattern described in the GCTA documentation for UKB-scale data:

```bash
PROJECT_ID=$(dx pwd | sed 's/:.*//')
GENO_DIR="/Bulk/Genotype Results/Genotype calls"
DEST="/Sool/Analysis/GCTA_Heritability/20260331_test_run/gcta_runs/grm_partitioned"
PARTS=250
THREADS=4
INSTANCE="mem2_ssd1_v2_x16"

DX_INPUTS=()
for chr in $(seq 1 22); do
  prefix="$GENO_DIR/ukb22418_c${chr}_b0_v2"
  DX_INPUTS+=("-iin=${PROJECT_ID}:${prefix}.bed")
  DX_INPUTS+=("-iin=${PROJECT_ID}:${prefix}.bim")
  DX_INPUTS+=("-iin=${PROJECT_ID}:${prefix}.fam")
done

for i in $(seq 1 ${PARTS}); do
  GCTA_CMD=$(cat <<EOF
set -euo pipefail
for chr in \$(seq 1 22); do
  echo "ukb22418_c\${chr}_b0_v2"
done > genotype_prefixes.mbfile

docker run --rm \
  -u "\$(id -u):\$(id -g)" \
  -w "\$PWD" \
  -v "\$PWD":"\$PWD" \
  quay.io/biocontainers/gcta:1.94.1--h9ee0642_0 \
  gcta64 \
    --mbfile genotype_prefixes.mbfile \
    --make-grm-part ${PARTS} ${i} \
    --thread-num ${THREADS} \
    --out blood_grm
EOF
)

  dx run app-swiss-army-knife \
    "${DX_INPUTS[@]}" \
    -icmd="$GCTA_CMD" \
    --instance-type "${INSTANCE}" \
    --destination "${PROJECT_ID}:${DEST}/parts" \
    --name "gcta-grm-part-${i}-of-${PARTS}" \
    --brief \
    --yes
done
```

Before merging, verify that all expected part files exist:

```bash
PART_DIR="/Sool/Analysis/GCTA_Heritability/20260331_test_run/gcta_runs/grm_partitioned/parts"
PARTS=250

for suffix in grm.id grm.bin grm.N.bin; do
  echo "${suffix}: $(dx find data --path "${PART_DIR}" --name "blood_grm.part_${PARTS}_*.${suffix}" --brief | wc -l)"
done
```

If any count is less than `250`, some part-jobs are still running or failed. To see which parts are missing:

```bash
PART_DIR="/Sool/Analysis/GCTA_Heritability/20260331_test_run/gcta_runs/grm_partitioned/parts"
PARTS=250

for i in $(seq 1 ${PARTS}); do
  for suffix in grm.id grm.bin grm.N.bin; do
    n=$(dx find data --path "${PART_DIR}" --name "blood_grm.part_${PARTS}_${i}.${suffix}" --brief | wc -l)
    if [ "$n" -eq 0 ]; then
      echo "missing: blood_grm.part_${PARTS}_${i}.${suffix}"
    fi
  done
done
```

After all part-jobs finish successfully, merge the parts in a second Swiss Army Knife job:

```bash
PROJECT_ID=$(dx pwd | sed 's/:.*//')
PART_DIR="/Sool/Analysis/GCTA_Heritability/20260331_test_run/gcta_runs/grm_partitioned/parts"
MERGE_DEST="/Sool/Analysis/GCTA_Heritability/20260331_test_run/gcta_runs/grm_partitioned/merged"
PARTS=250

DX_INPUTS=()
for i in $(seq 1 ${PARTS}); do
  for suffix in grm.id grm.bin grm.N.bin; do
    file_id=$(dx find data \
      --path "${PART_DIR}" \
      --name "blood_grm.part_${PARTS}_${i}.${suffix}" \
      --brief)
    if [ -z "$file_id" ]; then
      echo "Missing file: blood_grm.part_${PARTS}_${i}.${suffix}" >&2
      exit 1
    fi
    DX_INPUTS+=("-iin=${file_id}")
  done
done

MERGE_CMD=$(cat <<EOF
set -euo pipefail
: > blood_grm.grm.id
: > blood_grm.grm.bin
: > blood_grm.grm.N.bin
for i in \$(seq 1 ${PARTS}); do
  cat "blood_grm.part_${PARTS}_\${i}.grm.id" >> blood_grm.grm.id
  cat "blood_grm.part_${PARTS}_\${i}.grm.bin" >> blood_grm.grm.bin
  cat "blood_grm.part_${PARTS}_\${i}.grm.N.bin" >> blood_grm.grm.N.bin
done
EOF
)

dx run app-swiss-army-knife \
  "${DX_INPUTS[@]}" \
  -icmd="$MERGE_CMD" \
  --instance-type mem1_ssd1_v2_x4 \
  --destination "${PROJECT_ID}:${MERGE_DEST}" \
  --yes
```

Outputs after the merge step:
- `blood_grm.grm.id`
- `blood_grm.grm.bin`
- `blood_grm.grm.N.bin`

Warning:
- This partitioned workflow helps build the full dense GRM.
- It does not make full-sample GREML practical at ~488k samples. For heritability estimation, you will usually still want an unrelated/QC subset.
- If `dx find data` returns zero files in the `parts` folder, the merge step is premature. First confirm that the partition jobs were actually launched and completed successfully.

### Step 3c: Create an unrelated GRM from the merged full GRM

GCTA's own tutorial shows `--grm-cutoff 0.025 --make-grm` as the standard way to remove cryptic relatedness from a merged GRM, while noting that `0.025` is somewhat arbitrary.

Copy and paste:

```bash
PROJECT_ID=$(dx pwd | sed 's/:.*//')
MERGED_DIR="/Sool/Analysis/GCTA_Heritability/20260331_test_run/gcta_runs/grm_partitioned/merged"
DEST="/Sool/Analysis/GCTA_Heritability/20260331_test_run/gcta_runs/grm_unrelated"

dx run app-swiss-army-knife \
  -iin="${PROJECT_ID}:${MERGED_DIR}/blood_grm.grm.id" \
  -iin="${PROJECT_ID}:${MERGED_DIR}/blood_grm.grm.bin" \
  -iin="${PROJECT_ID}:${MERGED_DIR}/blood_grm.grm.N.bin" \
  -icmd='docker run --rm -u "$(id -u):$(id -g)" -w "$PWD" -v "$PWD":"$PWD" quay.io/biocontainers/gcta:1.94.1--h9ee0642_0 gcta64 --grm blood_grm --grm-cutoff 0.025 --make-grm --out blood_grm_rm025' \
  --instance-type mem2_ssd1_v2_x32 \
  --destination "${PROJECT_ID}:${DEST}" \
  --yes
```

Expected outputs:
- `blood_grm_rm025.grm.id`
- `blood_grm_rm025.grm.bin`
- `blood_grm_rm025.grm.N.bin`

The file `blood_grm_rm025.grm.id` is also a valid two-column keep list for later GREML jobs.

### Step 4: Run GREML one trait at a time

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

### Step 5: Summarize heritability

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
