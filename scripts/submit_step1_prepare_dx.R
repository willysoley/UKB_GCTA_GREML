#!/usr/bin/env Rscript

usage <- function() {
  cat(
    "Submit the Step 1 GCTA prep job on UKB RAP via Swiss Army Knife.\n\n",
    "Run this from the cloned repository directory inside /mnt/project,\n",
    "or call it from the RStudio console with:\n",
    "  system('Rscript scripts/submit_step1_prepare_dx.R --yes')\n\n",
    "Defaults:\n",
    "  phenotype:   <analysis_dir>/data/phenotype/raw_blood_phenotypes.csv\n",
    "  covariate:   /Sool/covariates_processed_all.tsv\n",
    "  fam:         /Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam\n",
    "  destination: <analysis_dir>/gcta_runs/prepare\n\n",
    "Usage:\n",
    "  Rscript scripts/submit_step1_prepare_dx.R [options]\n\n",
    "Options:\n",
    "  --phenotype <project_path>\n",
    "  --covariate <project_path>\n",
    "  --fam <project_path>\n",
    "  --destination <project_path>\n",
    "  --instance-type <dx_instance_type>\n",
    "  --traits \"<space separated trait codes>\"\n",
    "  --yes\n",
    "  -h, --help\n",
    sep = ""
  )
}

stopf <- function(...) {
  stop(sprintf(...), call. = FALSE)
}

run_cmd <- function(command, args) {
  out <- tryCatch(
    system2(command, args = args, stdout = TRUE, stderr = TRUE),
    warning = function(w) {
      attr(w, "status") <- 0L
      w
    }
  )

  status <- attr(out, "status")
  if (is.null(status)) {
    status <- 0L
  }

  list(status = status, output = out)
}

parse_args <- function(argv) {
  opts <- list(
    phenotype = NULL,
    covariate = "/Sool/covariates_processed_all.tsv",
    fam = "/Bulk/Genotype Results/Genotype calls/ukb22418_c1_b0_v2.fam",
    destination = NULL,
    instance_type = "mem2_ssd1_v2_x16",
    traits = "30000 30010 30020 30040 30050 30060 30080 30120 30130 30140",
    yes = FALSE
  )

  i <- 1L
  while (i <= length(argv)) {
    arg <- argv[[i]]

    if (arg %in% c("-h", "--help")) {
      usage()
      quit(save = "no", status = 0)
    } else if (arg == "--phenotype") {
      i <- i + 1L
      if (i > length(argv)) stopf("--phenotype requires a value")
      opts$phenotype <- argv[[i]]
    } else if (arg == "--covariate") {
      i <- i + 1L
      if (i > length(argv)) stopf("--covariate requires a value")
      opts$covariate <- argv[[i]]
    } else if (arg == "--fam") {
      i <- i + 1L
      if (i > length(argv)) stopf("--fam requires a value")
      opts$fam <- argv[[i]]
    } else if (arg == "--destination") {
      i <- i + 1L
      if (i > length(argv)) stopf("--destination requires a value")
      opts$destination <- argv[[i]]
    } else if (arg == "--instance-type") {
      i <- i + 1L
      if (i > length(argv)) stopf("--instance-type requires a value")
      opts$instance_type <- argv[[i]]
    } else if (arg == "--traits") {
      i <- i + 1L
      if (i > length(argv)) stopf("--traits requires a value")
      opts$traits <- argv[[i]]
    } else if (arg == "--yes") {
      opts$yes <- TRUE
    } else {
      stopf("Unknown argument: %s", arg)
    }

    i <- i + 1L
  }

  opts
}

if (Sys.which("dx") == "") {
  stopf("dx CLI is required but not found on PATH.")
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

cwd <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!startsWith(cwd, "/mnt/project/")) {
  stopf("Run this script from the cloned repo inside /mnt/project on RAP. Current directory: %s", cwd)
}

pwd_result <- run_cmd("dx", c("pwd"))
if (pwd_result$status != 0L || !length(pwd_result$output)) {
  stopf("Could not determine current DNAnexus project from 'dx pwd'.")
}

project_id <- sub(":.*$", "", pwd_result$output[[1]])
if (!startsWith(project_id, "project-")) {
  stopf("Unexpected dx pwd output: %s", pwd_result$output[[1]])
}

repo_project_path <- sub("^/mnt/project", "", cwd)
analysis_dir <- dirname(repo_project_path)

if (is.null(args$phenotype)) {
  args$phenotype <- paste0(analysis_dir, "/data/phenotype/raw_blood_phenotypes.csv")
}
if (is.null(args$destination)) {
  args$destination <- paste0(analysis_dir, "/gcta_runs/prepare")
}

repo_script_path <- paste0(repo_project_path, "/scripts/prepare_gcta_inputs.R")
icmd <- paste(
  "Rscript prepare_gcta_inputs.R",
  sprintf("--fam %s", shQuote(basename(args$fam))),
  sprintf("--pheno-csv %s", shQuote(basename(args$phenotype))),
  sprintf("--covar-csv %s", shQuote(basename(args$covariate))),
  "--covar-id-column IID",
  "--covar-preset ukb_blood_lab_shared",
  sprintf("--trait-codes %s", args$traits),
  "--num-pcs 20",
  "--outdir gcta_inputs"
)

cat("Submitting Step 1 prep job with:\n")
cat(sprintf("  project_id:   %s\n", project_id))
cat(sprintf("  repo_script:  %s\n", repo_script_path))
cat(sprintf("  phenotype:    %s\n", args$phenotype))
cat(sprintf("  covariate:    %s\n", args$covariate))
cat(sprintf("  fam:          %s\n", args$fam))
cat(sprintf("  destination:  %s\n", args$destination))
cat(sprintf("  instance:     %s\n", args$instance_type))
cat(sprintf("  traits:       %s\n", args$traits))

dx_args <- c(
  "run", "app-swiss-army-knife",
  sprintf("-iin=%s:%s", project_id, repo_script_path),
  sprintf("-iin=%s:%s", project_id, args$phenotype),
  sprintf("-iin=%s:%s", project_id, args$covariate),
  sprintf("-iin=%s:%s", project_id, args$fam),
  sprintf("-icmd=%s", icmd),
  "-imount_inputs=true",
  "--instance-type", args$instance_type,
  "--destination", sprintf("%s:%s", project_id, args$destination)
)

if (args$yes) {
  dx_args <- c(dx_args, "--yes")
}

status <- system2("dx", args = dx_args)
quit(save = "no", status = status)
