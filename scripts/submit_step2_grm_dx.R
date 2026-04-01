#!/usr/bin/env Rscript

usage <- function() {
  cat(
    "Submit a GRM-only GCTA job on UKB RAP via Swiss Army Knife.\n\n",
    "This launcher does not require the repo to live in project storage.\n",
    "It uses protected genotype objects from the current RAP project and\n",
    "submits a standalone GRM job.\n",
    "Inputs are staged inside the RAP job worker; nothing leaves RAP.\n\n",
    "Usage:\n",
    "  Rscript scripts/submit_step2_grm_dx.R [options]\n\n",
    "Options:\n",
    "  --genotype-dir <project_path>       Default: /Bulk/Genotype Results/Genotype calls\n",
    "  --prefix-template <sprintf_format>  Default: ukb22418_c%d_b0_v2\n",
    "  --chromosomes \"1 2 ... 22\"          Default: 1:22\n",
    "  --keep <project_path>               Optional keep file for unrelateds/sample subset\n",
    "  --threads <n>                       Default: 16\n",
    "  --instance-type <dx_type>           Default: mem2_ssd1_v2_x32\n",
    "  --destination <project_path>        Default: <current dx folder>/gcta_runs/grm\n",
    "  --out-prefix <job_output_prefix>    Default: grm/blood_grm\n",
    "  --yes\n",
    "  -h, --help\n\n",
    "Example:\n",
    "  Rscript scripts/submit_step2_grm_dx.R --yes\n",
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
    genotype_dir = "/Bulk/Genotype Results/Genotype calls",
    prefix_template = "ukb22418_c%d_b0_v2",
    chromosomes = as.character(1:22),
    keep = NULL,
    threads = 16L,
    instance_type = "mem2_ssd1_v2_x32",
    destination = NULL,
    out_prefix = "grm/blood_grm",
    yes = FALSE
  )

  i <- 1L
  while (i <= length(argv)) {
    arg <- argv[[i]]

    if (arg %in% c("-h", "--help")) {
      usage()
      quit(save = "no", status = 0)
    } else if (arg == "--genotype-dir") {
      i <- i + 1L
      if (i > length(argv)) stopf("--genotype-dir requires a value")
      opts$genotype_dir <- argv[[i]]
    } else if (arg == "--prefix-template") {
      i <- i + 1L
      if (i > length(argv)) stopf("--prefix-template requires a value")
      opts$prefix_template <- argv[[i]]
    } else if (arg == "--chromosomes") {
      i <- i + 1L
      if (i > length(argv)) stopf("--chromosomes requires a value")
      opts$chromosomes <- strsplit(argv[[i]], "[[:space:]]+")[[1]]
      opts$chromosomes <- opts$chromosomes[nzchar(opts$chromosomes)]
    } else if (arg == "--keep") {
      i <- i + 1L
      if (i > length(argv)) stopf("--keep requires a value")
      opts$keep <- argv[[i]]
    } else if (arg == "--threads") {
      i <- i + 1L
      if (i > length(argv)) stopf("--threads requires a value")
      opts$threads <- as.integer(argv[[i]])
    } else if (arg == "--instance-type") {
      i <- i + 1L
      if (i > length(argv)) stopf("--instance-type requires a value")
      opts$instance_type <- argv[[i]]
    } else if (arg == "--destination") {
      i <- i + 1L
      if (i > length(argv)) stopf("--destination requires a value")
      opts$destination <- argv[[i]]
    } else if (arg == "--out-prefix") {
      i <- i + 1L
      if (i > length(argv)) stopf("--out-prefix requires a value")
      opts$out_prefix <- argv[[i]]
    } else if (arg == "--yes") {
      opts$yes <- TRUE
    } else {
      stopf("Unknown argument: %s", arg)
    }

    i <- i + 1L
  }

  if (!length(opts$chromosomes)) {
    stopf("--chromosomes must include at least one chromosome")
  }

  opts
}

if (Sys.which("dx") == "") {
  stopf("dx CLI is required but not found on PATH.")
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

pwd_result <- run_cmd("dx", c("pwd"))
if (pwd_result$status != 0L || !length(pwd_result$output)) {
  stopf("Could not determine current DNAnexus project from 'dx pwd'.")
}

project_id <- sub(":.*$", "", pwd_result$output[[1]])
current_folder <- sub("^[^:]+:", "", pwd_result$output[[1]])

if (!startsWith(project_id, "project-")) {
  stopf("Unexpected dx pwd output: %s", pwd_result$output[[1]])
}

if (is.null(args$destination)) {
  args$destination <- paste0(current_folder, if (endsWith(current_folder, "/")) "" else "/", "gcta_runs/grm")
}

prefixes <- vapply(
  args$chromosomes,
  function(chr) sprintf(args$prefix_template, as.integer(chr)),
  character(1)
)

project_inputs <- unlist(lapply(prefixes, function(prefix) {
  file.path(args$genotype_dir, c(
    paste0(prefix, ".bed"),
    paste0(prefix, ".bim"),
    paste0(prefix, ".fam")
  ))
}), use.names = FALSE)

mbfile_lines <- paste(prefixes, collapse = "\\n")
keep_arg <- ""
input_args <- sprintf("-iin=%s:%s", project_id, project_inputs)

if (!is.null(args$keep)) {
  input_args <- c(input_args, sprintf("-iin=%s:%s", project_id, args$keep))
  keep_arg <- sprintf(" --keep %s", shQuote(basename(args$keep)))
}

icmd <- paste0(
  "mkdir -p grm && ",
  "cat > genotype_prefixes.mbfile <<'EOF'\n",
  paste(prefixes, collapse = "\n"),
  "\nEOF\n",
  "docker run --rm -u \"$(id -u):$(id -g)\" -w \"$PWD\" -v \"$PWD\":\"$PWD\" ",
  "quay.io/biocontainers/gcta:1.94.1--h9ee0642_0 ",
  "gcta64 --mbfile genotype_prefixes.mbfile --make-grm --thread-num ",
  args$threads,
  keep_arg,
  " --out ",
  args$out_prefix
)

cat("Submitting GRM job with:\n")
cat(sprintf("  project_id:      %s\n", project_id))
cat(sprintf("  genotype_dir:    %s\n", args$genotype_dir))
cat(sprintf("  chromosomes:     %s\n", paste(args$chromosomes, collapse = " ")))
cat(sprintf("  keep:            %s\n", if (is.null(args$keep)) "<none>" else args$keep))
cat(sprintf("  threads:         %s\n", args$threads))
cat(sprintf("  instance_type:   %s\n", args$instance_type))
cat(sprintf("  destination:     %s\n", args$destination))
cat(sprintf("  out_prefix:      %s\n", args$out_prefix))

dx_args <- c(
  "run", "app-swiss-army-knife",
  input_args,
  sprintf("-icmd=%s", icmd),
  "--instance-type", args$instance_type,
  "--destination", sprintf("%s:%s", project_id, args$destination)
)

if (args$yes) {
  dx_args <- c(dx_args, "--yes")
}

status <- system2("dx", args = dx_args)
quit(save = "no", status = status)
