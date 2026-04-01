#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Submit the Step 1 GCTA prep job on UKB RAP via Swiss Army Knife.

Run this from the cloned repository directory inside /mnt/project.

Defaults:
  phenotype:  <analysis_dir>/data/phenotype/raw_blood_phenotypes.csv
  covariate:  /Sool/covariates_processed_all.tsv
  fam:        /Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam
  destination:<analysis_dir>/gcta_runs/prepare

Usage:
  scripts/submit_step1_prepare_dx.sh [options]

Options:
  --phenotype <project_path>
  --covariate <project_path>
  --fam <project_path>
  --destination <project_path>
  --instance-type <dx_instance_type>
  --traits "<space separated trait codes>"
  --yes
  -h, --help

Example:
  scripts/submit_step1_prepare_dx.sh --yes
EOF
}

if ! command -v dx >/dev/null 2>&1; then
  echo "dx CLI is required but not found on PATH." >&2
  exit 1
fi

if [[ $# -gt 0 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

project_id="$(dx pwd | sed 's/:.*//')"
if [[ -z "$project_id" || "$project_id" != project-* ]]; then
  echo "Could not determine current DNAnexus project from 'dx pwd'." >&2
  exit 1
fi

cwd="${PWD}"
if [[ "$cwd" != /mnt/project/* ]]; then
  echo "Run this script from the cloned repo inside /mnt/project on RAP." >&2
  echo "Current directory: $cwd" >&2
  exit 1
fi

repo_project_path="${cwd#/mnt/project}"
analysis_dir="$(dirname "$repo_project_path")"

phenotype_path="${analysis_dir}/data/phenotype/raw_blood_phenotypes.csv"
covariate_path="/Sool/covariates_processed_all.tsv"
fam_path="/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam"
destination_path="${analysis_dir}/gcta_runs/prepare"
instance_type="mem2_ssd1_v2_x16"
traits="30000 30010 30020 30040 30050 30060 30080 30120 30130 30140"
auto_yes=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phenotype)
      phenotype_path="$2"
      shift 2
      ;;
    --covariate)
      covariate_path="$2"
      shift 2
      ;;
    --fam)
      fam_path="$2"
      shift 2
      ;;
    --destination)
      destination_path="$2"
      shift 2
      ;;
    --instance-type)
      instance_type="$2"
      shift 2
      ;;
    --traits)
      traits="$2"
      shift 2
      ;;
    --yes)
      auto_yes=1
      shift
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

repo_script_path="${repo_project_path}/scripts/prepare_gcta_inputs.R"
icmd="Rscript prepare_gcta_inputs.R --fam $(basename "$fam_path") --pheno-csv $(basename "$phenotype_path") --covar-csv $(basename "$covariate_path") --covar-id-column IID --covar-preset ukb_blood_lab_shared --trait-codes ${traits} --num-pcs 20 --outdir gcta_inputs"

echo "Submitting Step 1 prep job with:"
echo "  project_id:   $project_id"
echo "  repo_script:  $repo_script_path"
echo "  phenotype:    $phenotype_path"
echo "  covariate:    $covariate_path"
echo "  fam:          $fam_path"
echo "  destination:  $destination_path"
echo "  instance:     $instance_type"
echo "  traits:       $traits"

dx_cmd=(
  dx run app-swiss-army-knife
  "-iin=${project_id}:${repo_script_path}"
  "-iin=${project_id}:${phenotype_path}"
  "-iin=${project_id}:${covariate_path}"
  "-iin=${project_id}:${fam_path}"
  "-icmd=${icmd}"
  "-imount_inputs=true"
  "--instance-type" "${instance_type}"
  "--destination" "${project_id}:${destination_path}"
)

if [[ "$auto_yes" -eq 1 ]]; then
  dx_cmd+=("--yes")
fi

"${dx_cmd[@]}"
