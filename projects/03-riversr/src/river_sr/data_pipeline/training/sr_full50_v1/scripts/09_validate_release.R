file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

output_path <- river_sr_path(context, context$config$output$processed)
input_path <- river_sr_path(context, context$config$input$recovered_predictors)
manifest_path <- river_sr_path(context, context$config$output$manifest)
predictor_path <- file.path(context$project_dir, "config", "full50_predictors.txt")
required <- c(output_path, input_path, predictor_path)
missing <- required[!file.exists(required)]
river_sr_assert(length(missing) == 0L, paste("Release validation is missing files:", paste(missing, collapse = ", ")))

dataset <- data.table::fread(output_path, encoding = "UTF-8", na.strings = c("", "NA"))
recovered <- data.table::fread(input_path, encoding = "UTF-8", na.strings = c("", "NA"))
predictors <- readLines(predictor_path, warn = FALSE)
predictors <- predictors[nzchar(trimws(predictors))]

river_sr_assert(nrow(dataset) == 4485L, "Full50 V1 must contain 4,485 rows.")
river_sr_assert(ncol(dataset) == 121L, "Full50 V1 must contain 121 columns.")
river_sr_assert(!anyDuplicated(dataset$site_id), "Full50 V1 site IDs are not unique.")
river_sr_assert(length(predictors) == 50L, "Full50 V1 predictor manifest must contain 50 variables.")
river_sr_assert(all(predictors %in% names(dataset)), "Full50 V1 is missing a predictor.")
river_sr_assert(all(is.finite(as.matrix(dataset[, ..predictors]))), "Full50 V1 contains a non-finite predictor.")

canonical_columns <- setdiff(names(recovered), "site_id")
comparison <- merge(
  dataset[, c("site_id", canonical_columns), with = FALSE],
  recovered[is.finite(p0__sp_x), c("site_id", canonical_columns), with = FALSE],
  by = "site_id", suffixes = c("_release", "_canonical"), all = TRUE, sort = FALSE
)
river_sr_assert(nrow(comparison) == 4485L, "Canonical predictor comparison is incomplete.")
differences <- vapply(canonical_columns, function(column) {
  left <- comparison[[paste0(column, "_release")]]
  right <- comparison[[paste0(column, "_canonical")]]
  if (is.numeric(left) && is.numeric(right)) {
    sum((abs(left - right) > 0) | xor(is.na(left), is.na(right)), na.rm = TRUE)
  } else {
    sum(ifelse(is.na(left) & is.na(right), FALSE, left != right), na.rm = TRUE)
  }
}, integer(1L))
river_sr_assert(sum(differences) == 0L, "Full50 V1 differs from the recovered canonical predictor block.")

manifest <- list(
  project = context$config$project$id,
  status = "validated_historical_compatible",
  release_contract = "forward observation aggregation plus recovered frozen predictor block",
  inputs = list(
    observation = river_sr_file_record(river_sr_path(context, context$config$input$observation), context$repo_root),
    recovered_predictors = river_sr_file_record(input_path, context$repo_root),
    predictor_manifest = river_sr_file_record(predictor_path, context$repo_root)
  ),
  output = river_sr_file_record(output_path, context$repo_root),
  counts = list(rows = nrow(dataset), columns = ncol(dataset), predictors = length(predictors)),
  canonical_predictor_changed_cells = sum(differences),
  isolation = "No runtime input is read from reference/."
)
river_sr_write_json(manifest, manifest_path)
message(sprintf("09 complete: validated historical-compatible Full50 V1 release: %s", manifest_path))
