file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

output_path <- river_sr_path(context, context$config$output$processed)
full50_rds_path <- river_sr_path(context, context$config$output$full50)
baseline_path <- river_sr_path(context, context$config$input$baseline_full50)
snapshot_path <- river_sr_path(context, context$config$input$recovered_v2_snapshot)
supplement_path <- river_sr_path(context, context$config$input$observation_supplement)
inventory_path <- river_sr_path(context, context$config$input$feature_inventory)
manifest_path <- river_sr_path(context, context$config$output$manifest)
predictor_path <- file.path(context$project_dir, "config", "full50_predictors.txt")
config_path <- file.path(context$project_dir, "config", "default.yml")

required_files <- c(output_path, full50_rds_path, baseline_path, snapshot_path, supplement_path, inventory_path, predictor_path, config_path)
missing <- required_files[!file.exists(required_files)]
river_sr_assert(length(missing) == 0L, paste("Release validation is missing files:", paste(missing, collapse = ", ")))

dataset <- data.table::fread(output_path, encoding = "UTF-8", na.strings = c("", "NA"))
baseline <- data.table::fread(baseline_path, encoding = "UTF-8", na.strings = c("", "NA"))
snapshot <- data.table::fread(snapshot_path, encoding = "UTF-8", na.strings = c("", "NA"))
predictors <- readLines(predictor_path, warn = FALSE)
predictors <- predictors[nzchar(trimws(predictors))]

river_sr_assert(nrow(dataset) == as.integer(context$config$contract$full50_rows), "Full50 V2 row count differs from the contract.")
river_sr_assert(!anyDuplicated(dataset$row_id) && !anyDuplicated(dataset$site_id), "Full50 V2 identifiers are not unique.")
river_sr_assert(length(predictors) == as.integer(context$config$contract$full50_predictors), "Full50 predictor count differs from the contract.")
river_sr_assert(length(setdiff(predictors, names(dataset))) == 0L, "Full50 V2 is missing a predictor.")
predictor_matrix <- as.matrix(dataset[, ..predictors])
river_sr_assert(all(is.finite(predictor_matrix)), "Full50 V2 contains a non-finite predictor value.")

supplement_rows <- dataset[is_supplemental_site == TRUE]
base_rows <- dataset[is_supplemental_site == FALSE]
river_sr_assert(nrow(supplement_rows) == as.integer(context$config$contract$supplement_full50_rows), "Supplement Full50 count differs from the contract.")
river_sr_assert(nrow(base_rows) == as.integer(context$config$contract$base_training_rows), "Base Full50 count differs from the contract.")

overall_bands <- table(factor(river_sr_sr_band(dataset$sr87_sr86), levels = names(context$config$contract$sr_bands)))
supplement_bands <- table(factor(river_sr_sr_band(supplement_rows$sr87_sr86), levels = names(context$config$contract$supplement_sr_bands)))
river_sr_assert(identical(as.integer(overall_bands), as.integer(unlist(context$config$contract$sr_bands))), "Overall Sr-band counts differ from the contract.")
river_sr_assert(identical(as.integer(supplement_bands), as.integer(unlist(context$config$contract$supplement_sr_bands))), "Supplement Sr-band counts differ from the contract.")

response_comparison <- merge(
  baseline[, c("site_id", "sr87_sr86", predictors), with = FALSE],
  base_rows[, c("site_id", "sr87_sr86", predictors), with = FALSE],
  by = "site_id", suffixes = c("_v1", "_v2"), all = TRUE, sort = FALSE
)
river_sr_assert(nrow(response_comparison) == as.integer(context$config$contract$base_training_rows), "V1/V2 base-site comparison is incomplete.")
river_sr_assert(!anyNA(response_comparison$sr87_sr86_v1) && !anyNA(response_comparison$sr87_sr86_v2), "A V1 site is missing from V2.")
response_difference <- max(abs(response_comparison$sr87_sr86_v1 - response_comparison$sr87_sr86_v2))
river_sr_assert(response_difference <= 1e-12, "V2 changed one or more base responses.")

snapshot_comparison <- merge(
  dataset[, c("legacy_site_id", "sr87_sr86", predictors), with = FALSE],
  snapshot[, c("site_id", "sr87_sr86", predictors), with = FALSE],
  by.x = "legacy_site_id", by.y = "site_id", suffixes = c("_release", "_canonical"),
  all = TRUE, sort = FALSE
)
river_sr_assert(nrow(snapshot_comparison) == as.integer(context$config$contract$full50_rows), "Recovered V2 comparison is incomplete.")
river_sr_assert(max(abs(snapshot_comparison$sr87_sr86_release - snapshot_comparison$sr87_sr86_canonical)) <= 1e-12, "V2 responses differ from the recovered release.")
canonical_differences <- vapply(predictors, function(name) {
  max(abs(snapshot_comparison[[paste0(name, "_release")]] - snapshot_comparison[[paste0(name, "_canonical")]]))
}, numeric(1L))
river_sr_assert(max(canonical_differences) <= 1e-10, "V2 predictors differ from the recovered 5,600-site release.")

v1_changed_cells <- sum(vapply(predictors, function(name) {
  sum(abs(response_comparison[[paste0(name, "_v1")]] - response_comparison[[paste0(name, "_v2")]]) > 1e-10)
}, integer(1L)))

source_site_counts <- sort(table(supplement_rows$source_datasets), decreasing = TRUE)
manifest <- list(
  project = context$config$project$id,
  status = "validated",
  inputs = list(
    base_observations = river_sr_file_record(river_sr_path(context, context$config$input$observation_base), context$repo_root),
    supplement_observations = river_sr_file_record(supplement_path, context$repo_root),
    baseline_full50 = river_sr_file_record(baseline_path, context$repo_root),
    recovered_v2_snapshot = river_sr_file_record(snapshot_path, context$repo_root),
    raw_feature_inventory = river_sr_file_record(inventory_path, context$repo_root),
    config = river_sr_file_record(config_path, context$repo_root),
    predictor_manifest = river_sr_file_record(predictor_path, context$repo_root)
  ),
  outputs = list(
    csv = river_sr_file_record(output_path, context$repo_root),
    rds = river_sr_file_record(full50_rds_path, context$repo_root)
  ),
  counts = list(
    rows = nrow(dataset),
    base_rows = nrow(base_rows),
    supplement_rows = nrow(supplement_rows),
    predictors = length(predictors),
    hydrological_l6 = data.table::uniqueN(dataset$r47__current_hybas_id),
    references = data.table::uniqueN(dataset$reference_id),
    overall_sr_bands = river_sr_named_counts(overall_bands),
    supplement_sr_bands = river_sr_named_counts(supplement_bands),
    supplement_source_sites = river_sr_named_counts(source_site_counts)
  ),
  alignment = list(
    base_site_ids_and_responses = "exact",
    max_abs_response_difference = response_difference,
    v2_predictors_match_recovered_5600_release = "exact_within_tolerance",
    max_abs_v2_predictor_difference = max(canonical_differences),
    base_predictor_cells_changed_from_v1 = v1_changed_cells,
    note = "Historical V2 re-extracted predictors for the old 4,485 sites; V1 predictor preservation is not a valid V2 contract.",
    numeric_tolerance = 1e-10
  ),
  isolation = "No runtime input is read from reference/."
)
river_sr_write_json(manifest, manifest_path)
message(sprintf("09 complete: validated and manifested %d x %d Full50 V2 release: %s", nrow(dataset), ncol(dataset), manifest_path))
