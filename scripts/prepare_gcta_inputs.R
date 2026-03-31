#!/usr/bin/env Rscript

default_traits <- c(
  "30000", "30010", "30020", "30040", "30050",
  "30060", "30080", "30120", "30130", "30140"
)

delimiters <- c(",", "\t", ";", "|")

usage <- function() {
  cat(
    "Usage:\n",
    "  prepare_gcta_inputs.R --fam <file> --pheno-csv <file> [options]\n\n",
    "Required:\n",
    "  --fam <file>                  Path to PLINK .fam file\n",
    "  --pheno-csv <file>            Phenotype CSV/TSV path\n\n",
    "Optional:\n",
    "  --covar-csv <file>            Covariate CSV/TSV path (default: phenotype file)\n",
    "  --outdir <dir>                Output directory (default: gcta_inputs)\n",
    "  --trait-codes <codes...>      Trait codes to process\n",
    "  --trait-column-template <s>   Trait column template (default: participant.p{code}_i0)\n",
    "  --id-column <name>            Default phenotype ID column (default: participant.eid)\n",
    "  --pheno-id-column <name>      Explicit phenotype ID column override\n",
    "  --covar-id-column <name>      Explicit covariate ID column\n",
    "  --fam-id-column <IID|FID>     Which FAM field is matched (default: IID)\n",
    "  --covar-cols <cols...>        Explicit categorical covariate columns\n",
    "  --qcovar-cols <cols...>       Explicit quantitative covariate columns\n",
    "  --covar-preset <name>         One of: auto, ukb_greml_common, ukb_blood_lab_shared\n",
    "  --age-col <name>              Age column name (default: participant.p21022)\n",
    "  --pc-prefix <prefix>          PC prefix (default: participant.p22009_a)\n",
    "  --num-pcs <n>                 Number of PCs to include (default: 20)\n",
    "  --add-age-squared             Append age^2 to qcovar output\n",
    "  --missing-values <vals...>    Tokens treated as missing\n",
    "  -h, --help                    Show this help\n",
    sep = ""
  )
}

stopf <- function(...) {
  message(sprintf(...))
  quit(save = "no", status = 1)
}

next_values <- function(argv, start_index) {
  values <- character()
  i <- start_index
  while (i <= length(argv) && !startsWith(argv[[i]], "--") && argv[[i]] != "-h") {
    values <- c(values, argv[[i]])
    i <- i + 1
  }
  list(values = values, next_index = i)
}

parse_args <- function(argv) {
  opts <- list(
    fam = NULL,
    pheno_csv = NULL,
    covar_csv = NULL,
    outdir = "gcta_inputs",
    trait_codes = default_traits,
    trait_column_template = "participant.p{code}_i0",
    id_column = "participant.eid",
    pheno_id_column = NULL,
    covar_id_column = NULL,
    fam_id_column = "IID",
    covar_cols = NULL,
    qcovar_cols = NULL,
    covar_preset = "auto",
    age_col = "participant.p21022",
    pc_prefix = "participant.p22009_a",
    num_pcs = 20L,
    add_age_squared = FALSE,
    missing_values = c("", "NA", "NaN", "nan", "NULL", "null", "-9")
  )

  i <- 1
  while (i <= length(argv)) {
    arg <- argv[[i]]

    if (arg %in% c("-h", "--help")) {
      usage()
      quit(save = "no", status = 0)
    } else if (arg == "--fam") {
      i <- i + 1
      if (i > length(argv)) stopf("--fam requires a value")
      opts$fam <- argv[[i]]
    } else if (arg == "--pheno-csv") {
      i <- i + 1
      if (i > length(argv)) stopf("--pheno-csv requires a value")
      opts$pheno_csv <- argv[[i]]
    } else if (arg == "--covar-csv") {
      i <- i + 1
      if (i > length(argv)) stopf("--covar-csv requires a value")
      opts$covar_csv <- argv[[i]]
    } else if (arg == "--outdir") {
      i <- i + 1
      if (i > length(argv)) stopf("--outdir requires a value")
      opts$outdir <- argv[[i]]
    } else if (arg == "--trait-column-template") {
      i <- i + 1
      if (i > length(argv)) stopf("--trait-column-template requires a value")
      opts$trait_column_template <- argv[[i]]
    } else if (arg == "--id-column") {
      i <- i + 1
      if (i > length(argv)) stopf("--id-column requires a value")
      opts$id_column <- argv[[i]]
    } else if (arg == "--pheno-id-column") {
      i <- i + 1
      if (i > length(argv)) stopf("--pheno-id-column requires a value")
      opts$pheno_id_column <- argv[[i]]
    } else if (arg == "--covar-id-column") {
      i <- i + 1
      if (i > length(argv)) stopf("--covar-id-column requires a value")
      opts$covar_id_column <- argv[[i]]
    } else if (arg == "--fam-id-column") {
      i <- i + 1
      if (i > length(argv)) stopf("--fam-id-column requires a value")
      opts$fam_id_column <- argv[[i]]
    } else if (arg == "--covar-preset") {
      i <- i + 1
      if (i > length(argv)) stopf("--covar-preset requires a value")
      opts$covar_preset <- argv[[i]]
    } else if (arg == "--age-col") {
      i <- i + 1
      if (i > length(argv)) stopf("--age-col requires a value")
      opts$age_col <- argv[[i]]
    } else if (arg == "--pc-prefix") {
      i <- i + 1
      if (i > length(argv)) stopf("--pc-prefix requires a value")
      opts$pc_prefix <- argv[[i]]
    } else if (arg == "--num-pcs") {
      i <- i + 1
      if (i > length(argv)) stopf("--num-pcs requires a value")
      opts$num_pcs <- as.integer(argv[[i]])
    } else if (arg == "--add-age-squared") {
      opts$add_age_squared <- TRUE
    } else if (arg %in% c("--trait-codes", "--covar-cols", "--qcovar-cols", "--missing-values")) {
      parsed <- next_values(argv, i + 1)
      field_name <- switch(
        arg,
        "--trait-codes" = "trait_codes",
        "--covar-cols" = "covar_cols",
        "--qcovar-cols" = "qcovar_cols",
        "--missing-values" = "missing_values"
      )
      opts[[field_name]] <- parsed$values
      i <- parsed$next_index - 1
    } else {
      stopf("Unknown argument: %s", arg)
    }

    i <- i + 1
  }

  if (is.null(opts$fam) || is.null(opts$pheno_csv)) {
    usage()
    stopf("--fam and --pheno-csv are required")
  }
  if (!opts$fam_id_column %in% c("IID", "FID")) {
    stopf("--fam-id-column must be IID or FID")
  }
  if (!opts$covar_preset %in% c("auto", "ukb_greml_common", "ukb_blood_lab_shared")) {
    stopf("--covar-preset must be one of: auto, ukb_greml_common, ukb_blood_lab_shared")
  }
  opts
}

normalize_id <- function(x) {
  out <- trimws(as.character(x))
  out[out == ""] <- NA_character_
  out <- sub("^([0-9]+)\\.0$", "\\1", out)
  out
}

is_missing_value <- function(x, missing_tokens) {
  is.na(x) | trimws(as.character(x)) %in% missing_tokens
}

read_fam <- function(fam_path) {
  fam <- utils::read.table(
    fam_path,
    header = FALSE,
    stringsAsFactors = FALSE,
    fill = TRUE,
    quote = "",
    comment.char = ""
  )
  if (ncol(fam) < 2) {
    stopf("Malformed FAM file: expected at least 2 columns in %s", fam_path)
  }
  fam <- fam[, 1:2, drop = FALSE]
  names(fam) <- c("FID", "IID")
  fam
}

detect_delimiter <- function(path) {
  lines <- readLines(path, n = 5L, warn = FALSE)
  sample_text <- paste(lines, collapse = "\n")
  if (!nzchar(sample_text)) {
    return(",")
  }
  counts <- vapply(delimiters, function(d) {
    total <- lengths(strsplit(sample_text, d, fixed = TRUE))
    sum(total) - length(total)
  }, numeric(1))
  best <- delimiters[[which.max(counts)]]
  if (counts[[which.max(counts)]] <= 0) "," else best
}

read_table_headers <- function(path, delimiter) {
  header_line <- readLines(path, n = 1L, warn = FALSE)
  if (!length(header_line)) {
    stopf("Table appears empty: %s", path)
  }
  strsplit(header_line, delimiter, fixed = TRUE)[[1]]
}

read_table_selected <- function(path, delimiter, selected_columns, missing_values) {
  headers <- read_table_headers(path, delimiter)
  keep <- headers %in% selected_columns
  col_classes <- ifelse(keep, "character", "NULL")
  na_values <- unique(setdiff(missing_values, ""))

  df <- utils::read.table(
    path,
    sep = delimiter,
    header = TRUE,
    stringsAsFactors = FALSE,
    quote = "\"",
    comment.char = "",
    check.names = FALSE,
    fill = TRUE,
    colClasses = col_classes,
    na.strings = na_values
  )

  if (!nrow(df)) {
    return(df)
  }
  df
}

first_existing <- function(headers, candidates) {
  for (candidate in candidates) {
    if (!is.na(candidate) && nzchar(candidate) && candidate %in% headers) {
      return(candidate)
    }
  }
  NULL
}

ordered_unique <- function(values) {
  values <- values[!is.na(values) & nzchar(values)]
  unique(values)
}

resolve_id_column <- function(headers, preferred = NULL, fallbacks = character()) {
  candidates <- ordered_unique(c(preferred, fallbacks))
  found <- first_existing(headers, candidates)
  if (is.null(found)) {
    stopf(
      "Could not find ID column. Tried: %s. Available columns include: %s",
      paste(candidates, collapse = ", "),
      paste(utils::head(headers, 10), collapse = ", ")
    )
  }
  found
}

find_numbered_columns <- function(headers, prefixes, n) {
  found <- character()
  for (i in seq_len(n)) {
    candidates <- paste0(prefixes, i)
    col <- first_existing(headers, candidates)
    if (!is.null(col) && !col %in% found) {
      found <- c(found, col)
    }
  }
  found
}

discover_trait_columns <- function(headers, trait_codes, template) {
  trait_map <- list()
  for (code in trait_codes) {
    candidates <- c(
      gsub("\\{code\\}", code, template),
      paste0("participant.p", code, "_i0"),
      paste0("p", code, "_i0"),
      paste0("participant.p", code),
      code
    )
    col <- first_existing(headers, candidates)
    if (!is.null(col)) {
      trait_map[[code]] <- col
    }
  }
  trait_map
}

discover_default_covar_cols <- function(headers) {
  ordered_unique(c(
    first_existing(headers, c("participant.p31", "participant.p31_i0", "p31", "sex", "p31_Male")),
    first_existing(headers, c("Array", "array", "participant.p22000", "participant.p22000_i0", "p22000")),
    first_existing(headers, c("participant.p54_i0", "participant.p54", "p54_i0", "p54", "assessment_center"))
  ))
}

discover_default_qcovar_cols <- function(headers, age_col, pc_prefix, num_pcs) {
  age_found <- first_existing(headers, c(age_col, "participant.p21022", "participant.p21022_i0", "p21022", "age"))
  qcovars <- ordered_unique(c(
    age_found,
    find_numbered_columns(headers, c(pc_prefix, "participant.p22009_a", "p22009_a", "PC", "pc"), num_pcs)
  ))
  list(covars = qcovars, age_col = age_found)
}

discover_ukb_greml_common <- function(headers, age_col, pc_prefix, num_pcs) {
  age_found <- first_existing(headers, c(age_col, "participant.p21022", "participant.p21022_i0", "p21022", "age"))
  sex_binary <- first_existing(headers, c("p31_Male", "participant.p31_Male", "sex_male"))
  sex_general <- first_existing(headers, c("participant.p31", "participant.p31_i0", "p31", "sex"))

  covars <- ordered_unique(c(
    first_existing(headers, c("Array", "array")),
    first_existing(headers, c("participant.p22000", "participant.p22000_i0", "p22000")),
    first_existing(headers, c("participant.p54_i0", "participant.p54", "p54_i0", "p54", "assessment_center")),
    if (is.null(sex_binary)) sex_general else NULL
  ))

  qcovars <- ordered_unique(c(
    sex_binary,
    age_found,
    find_numbered_columns(headers, c(pc_prefix, "participant.p22009_a", "p22009_a"), num_pcs)
  ))

  list(covar_cols = covars, qcovar_cols = qcovars, age_col = age_found)
}

discover_ukb_blood_lab_shared <- function(headers, age_col, pc_prefix, num_pcs) {
  age_found <- first_existing(headers, c(age_col, "participant.p21022", "participant.p21022_i0", "p21022", "age"))
  sex_binary <- first_existing(headers, c("p31_Male", "participant.p31_Male", "sex_male"))
  sex_general <- first_existing(headers, c("participant.p31", "participant.p31_i0", "p31", "sex"))

  covars <- ordered_unique(c(
    first_existing(headers, c("Array", "array")),
    first_existing(headers, c("participant.p22000", "participant.p22000_i0", "p22000")),
    first_existing(headers, c("participant.p54_i0", "participant.p54", "p54_i0", "p54", "assessment_center")),
    first_existing(headers, c("participant.p32050", "p32050")),
    first_existing(headers, c("participant.p32053", "p32053")),
    if (is.null(sex_binary)) sex_general else NULL
  ))

  qcovars <- ordered_unique(c(
    sex_binary,
    age_found,
    first_existing(headers, c("p21022_squared", "participant.p21022_squared", "age_squared", "age2")),
    first_existing(headers, c("p21022_by_p31_Male", "participant.p21022_by_p31_Male", "age_by_sex", "age_sex")),
    first_existing(headers, c(
      "p21022squared_by_p31_Male",
      "participant.p21022squared_by_p31_Male",
      "age_squared_by_sex",
      "age2_by_sex"
    )),
    find_numbered_columns(headers, c(pc_prefix, "participant.p22009_a", "p22009_a"), num_pcs),
    find_numbered_columns(headers, c("PC", "pc"), num_pcs)
  ))

  list(covar_cols = covars, qcovar_cols = qcovars, age_col = age_found)
}

row_has_missing <- function(df, missing_tokens) {
  if (!ncol(df)) {
    return(rep(FALSE, nrow(df)))
  }
  missing_by_col <- lapply(df, function(col) is_missing_value(col, missing_tokens))
  Reduce(`|`, missing_by_col)
}

write_tab_table <- function(df, path) {
  utils::write.table(
    df,
    file = path,
    sep = "\t",
    quote = FALSE,
    row.names = FALSE,
    col.names = FALSE,
    na = ""
  )
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

fam_path <- args$fam
pheno_path <- args$pheno_csv
covar_path <- if (is.null(args$covar_csv)) args$pheno_csv else args$covar_csv
outdir <- args$outdir

fam_rows <- read_fam(fam_path)
pheno_delim <- detect_delimiter(pheno_path)
covar_delim <- detect_delimiter(covar_path)

pheno_headers <- read_table_headers(pheno_path, pheno_delim)
pheno_id_col <- resolve_id_column(
  pheno_headers,
  preferred = if (!is.null(args$pheno_id_column)) args$pheno_id_column else args$id_column,
  fallbacks = c("participant.eid", "eid", "IID", "FID")
)

trait_map <- discover_trait_columns(pheno_headers, args$trait_codes, args$trait_column_template)
missing_traits <- setdiff(args$trait_codes, names(trait_map))

covar_headers <- read_table_headers(covar_path, covar_delim)
covar_id_col <- resolve_id_column(
  covar_headers,
  preferred = args$covar_id_column,
  fallbacks = c(pheno_id_col, args$id_column, "participant.eid", "eid", "IID", "FID")
)

age_col_found <- NULL

if (is.null(args$covar_cols) && is.null(args$qcovar_cols)) {
  preset <- switch(
    args$covar_preset,
    "ukb_greml_common" = discover_ukb_greml_common(covar_headers, args$age_col, args$pc_prefix, args$num_pcs),
    "ukb_blood_lab_shared" = discover_ukb_blood_lab_shared(covar_headers, args$age_col, args$pc_prefix, args$num_pcs),
    {
      default_q <- discover_default_qcovar_cols(covar_headers, args$age_col, args$pc_prefix, args$num_pcs)
      list(
        covar_cols = discover_default_covar_cols(covar_headers),
        qcovar_cols = default_q$covars,
        age_col = default_q$age_col
      )
    }
  )
  covar_cols <- preset$covar_cols
  qcovar_cols <- preset$qcovar_cols
  age_col_found <- preset$age_col
} else {
  covar_cols <- if (is.null(args$covar_cols)) discover_default_covar_cols(covar_headers) else intersect(args$covar_cols, covar_headers)
  if (is.null(args$qcovar_cols)) {
    default_q <- discover_default_qcovar_cols(covar_headers, args$age_col, args$pc_prefix, args$num_pcs)
    qcovar_cols <- default_q$covars
    age_col_found <- default_q$age_col
  } else {
    qcovar_cols <- intersect(args$qcovar_cols, covar_headers)
    age_col_found <- first_existing(qcovar_cols, c(args$age_col, "participant.p21022", "participant.p21022_i0", "p21022", "age"))
  }
}

covar_cols <- ordered_unique(covar_cols)
qcovar_cols <- ordered_unique(qcovar_cols)

selected_pheno_cols <- ordered_unique(c(pheno_id_col, unlist(trait_map, use.names = FALSE)))
selected_covar_cols <- ordered_unique(c(covar_id_col, covar_cols, qcovar_cols))

pheno_data <- read_table_selected(pheno_path, pheno_delim, selected_pheno_cols, args$missing_values)
covar_data <- read_table_selected(covar_path, covar_delim, selected_covar_cols, args$missing_values)

pheno_data$id_norm <- normalize_id(pheno_data[[pheno_id_col]])
pheno_data <- pheno_data[!is.na(pheno_data$id_norm) & !duplicated(pheno_data$id_norm), , drop = FALSE]

covar_data$id_norm <- normalize_id(covar_data[[covar_id_col]])
covar_data <- covar_data[!is.na(covar_data$id_norm) & !duplicated(covar_data$id_norm), , drop = FALSE]

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
traits_root <- file.path(outdir, "traits")
dir.create(traits_root, recursive = TRUE, showWarnings = FALSE)

selected_covars_path <- file.path(outdir, "covariate_selection.txt")
writeLines(
  c(
    paste("pheno_file", pheno_path, sep = "\t"),
    paste("covar_file", covar_path, sep = "\t"),
    paste("pheno_delimiter", shQuote(pheno_delim), sep = "\t"),
    paste("covar_delimiter", shQuote(covar_delim), sep = "\t"),
    paste("pheno_id_column", pheno_id_col, sep = "\t"),
    paste("covar_id_column", covar_id_col, sep = "\t"),
    paste("covar_preset", args$covar_preset, sep = "\t"),
    paste("covar_columns", paste(covar_cols, collapse = ","), sep = "\t"),
    paste("qcovar_columns", paste(qcovar_cols, collapse = ","), sep = "\t")
  ),
  con = selected_covars_path
)

sample_id <- normalize_id(if (args$fam_id_column == "IID") fam_rows$IID else fam_rows$FID)
pheno_match <- match(sample_id, pheno_data$id_norm)
covar_match <- match(sample_id, covar_data$id_norm)

summary_rows <- list()

for (trait in args$trait_codes) {
  if (!trait %in% names(trait_map)) {
    next
  }

  trait_col <- trait_map[[trait]]
  trait_dir <- file.path(traits_root, trait)
  dir.create(trait_dir, recursive = TRUE, showWarnings = FALSE)

  phen_path <- file.path(trait_dir, paste0(trait, ".phen"))
  covar_out_path <- file.path(trait_dir, paste0(trait, ".covar"))
  qcovar_out_path <- file.path(trait_dir, paste0(trait, ".qcovar"))
  keep_path <- file.path(trait_dir, paste0(trait, ".keep"))

  pheno_present <- !is.na(pheno_match)
  y_values <- rep(NA_character_, length(sample_id))
  y_values[pheno_present] <- pheno_data[[trait_col]][pheno_match[pheno_present]]
  pheno_missing <- is_missing_value(y_values, args$missing_values)

  covar_present <- !is.na(covar_match)
  aligned_covar <- if (length(covar_cols)) covar_data[covar_match, covar_cols, drop = FALSE] else data.frame(row.names = seq_along(sample_id))
  aligned_qcovar <- if (length(qcovar_cols)) covar_data[covar_match, qcovar_cols, drop = FALSE] else data.frame(row.names = seq_along(sample_id))

  covar_missing <- !covar_present | row_has_missing(aligned_covar, args$missing_values) | row_has_missing(aligned_qcovar, args$missing_values)

  age_sq_values <- rep(NA_character_, length(sample_id))
  if (args$add_age_squared && !is.null(age_col_found)) {
    age_present <- aligned_qcovar[[age_col_found]]
    suppressWarnings(age_numeric <- as.numeric(age_present))
    age_sq_values <- ifelse(is.na(age_numeric), NA_character_, sprintf("%.8f", age_numeric * age_numeric))
    covar_missing <- covar_missing | is.na(age_sq_values)
  }

  keep_mask <- pheno_present & !pheno_missing & !covar_missing

  phen_df <- data.frame(
    FID = fam_rows$FID[keep_mask],
    IID = fam_rows$IID[keep_mask],
    PHENO = y_values[keep_mask],
    stringsAsFactors = FALSE
  )

  covar_df <- data.frame(
    FID = fam_rows$FID[keep_mask],
    IID = fam_rows$IID[keep_mask],
    aligned_covar[keep_mask, , drop = FALSE],
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  qcovar_df <- data.frame(
    FID = fam_rows$FID[keep_mask],
    IID = fam_rows$IID[keep_mask],
    aligned_qcovar[keep_mask, , drop = FALSE],
    stringsAsFactors = FALSE,
    check.names = FALSE
  )

  if (args$add_age_squared && !is.null(age_col_found)) {
    qcovar_df$age_squared <- age_sq_values[keep_mask]
  }

  keep_df <- data.frame(
    FID = fam_rows$FID[keep_mask],
    IID = fam_rows$IID[keep_mask],
    stringsAsFactors = FALSE
  )

  write_tab_table(phen_df, phen_path)
  write_tab_table(covar_df, covar_out_path)
  write_tab_table(qcovar_df, qcovar_out_path)
  write_tab_table(keep_df, keep_path)

  summary_rows[[length(summary_rows) + 1L]] <- data.frame(
    trait = trait,
    trait_column = trait_col,
    n_analyzed = sum(keep_mask),
    dropped_missing_pheno = sum(pheno_present & pheno_missing),
    dropped_missing_covars = sum(pheno_present & !pheno_missing & covar_missing),
    stringsAsFactors = FALSE
  )
}

summary_df <- if (length(summary_rows)) do.call(rbind, summary_rows) else data.frame(
  trait = character(),
  trait_column = character(),
  n_analyzed = integer(),
  dropped_missing_pheno = integer(),
  dropped_missing_covars = integer(),
  stringsAsFactors = FALSE
)

manifest_path <- file.path(outdir, "trait_manifest.tsv")
utils::write.table(
  summary_df,
  file = manifest_path,
  sep = "\t",
  quote = FALSE,
  row.names = FALSE
)

traits_to_run <- summary_df$trait[summary_df$n_analyzed > 0]
trait_list_path <- file.path(outdir, "traits_to_run.txt")
writeLines(traits_to_run, con = trait_list_path)

cat(sprintf("Wrote manifest: %s\n", manifest_path))
cat(sprintf("Wrote trait list: %s\n", trait_list_path))
cat(sprintf("Wrote covariate selection: %s\n", selected_covars_path))
cat(sprintf("Prepared traits with data: %d / %d\n", sum(summary_df$n_analyzed > 0), length(args$trait_codes)))

if (length(missing_traits)) {
  warning(sprintf("Trait codes not found in phenotype columns: %s", paste(missing_traits, collapse = ", ")), call. = FALSE)
}

empty_traits <- summary_df$trait[summary_df$n_analyzed == 0]
if (length(empty_traits)) {
  warning(sprintf("No analyzable rows after filtering for traits: %s", paste(empty_traits, collapse = ", ")), call. = FALSE)
}

if (!length(covar_cols)) {
  warning("No categorical covariates selected.", call. = FALSE)
}

if (!length(qcovar_cols) && !(args$add_age_squared && !is.null(age_col_found))) {
  warning("No quantitative covariates selected.", call. = FALSE)
}
