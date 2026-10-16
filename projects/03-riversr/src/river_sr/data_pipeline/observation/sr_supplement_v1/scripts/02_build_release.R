file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- supplement_context(script_path)

input_path <- supplement_path(context, context$config$output$validated)
raw_path <- supplement_path(context, context$config$input$raw)
output_path <- supplement_path(context, context$config$output$processed)
manifest_path <- supplement_path(context, context$config$output$manifest)
supplement_assert(file.exists(input_path), paste("Run step 01 first; missing:", input_path))

raw <- data.table::as.data.table(readRDS(input_path))
release <- data.table::copy(raw)
release[, `:=`(
  sample_id = paste0("supplement_v1__", supplement_id),
  material_id = paste0("supplement_v1__", supplement_id),
  original_sample_id = as.character(source_record_id),
  original_material_id = as.character(source_dataset),
  coordinates_type = "source_reported",
  short_references = as.character(source_reference),
  material_type = "water",
  sample_type = as.character(sample_fraction),
  sr87_sr86_uncertainty_type = NA_character_,
  sr_concentration_ppm_uncertainty = NA_real_,
  sr_concentration_uncertainty_type = NA_character_,
  dataset_doi = data.table::fifelse(!is.na(data_doi) & nzchar(data_doi), data_doi, article_doi),
  analytical_parameters_id = NA_character_,
  context = "environmental",
  qc_include_training = possible_existing_match != "yes"
)]

compatibility <- c(
  "sample_id", "material_id", "original_sample_id", "original_material_id",
  "location_name", "latitude", "longitude", "coordinates_type", "short_references",
  "material_type", "water_provenance", "sample_type", "sr87_sr86",
  "sr87_sr86_uncertainty", "sr87_sr86_uncertainty_type", "sr_concentration_ppm",
  "sr_concentration_ppm_uncertainty", "sr_concentration_uncertainty_type",
  "dataset_doi", "analytical_parameters_id", "context"
)
provenance <- setdiff(names(release), compatibility)
data.table::setcolorder(release, c(compatibility, provenance))
data.table::setorder(release, source_dataset, supplement_id)

training <- release[qc_include_training == TRUE]
coordinate_key <- paste(round(training$longitude, 5L), round(training$latitude, 5L), sep = "_")
supplement_assert(nrow(training) == as.integer(context$config$contract$training_rows), "Training-eligible row count differs from the contract.")
supplement_assert(length(unique(coordinate_key)) == as.integer(context$config$contract$training_coordinate5_sites), "Training-eligible coordinate-site count differs from the contract.")

supplement_atomic_csv(release, output_path)
manifest <- list(
  project = context$config$project$id,
  status = "built",
  inputs = list(supplement_file_record(raw_path, context$repo_root)),
  output = supplement_file_record(output_path, context$repo_root),
  counts = list(
    rows = nrow(release),
    sources = data.table::uniqueN(release$source_dataset),
    training_rows = nrow(training),
    excluded_possible_existing_matches = sum(!release$qc_include_training),
    training_coordinate5_sites = length(unique(coordinate_key)),
    source_rows = supplement_named_counts(table(release$source_dataset)),
    sr_bands = supplement_named_counts(table(factor(release$sr_band, levels = names(context$config$contract$sr_bands))))
  ),
  rule = "possible_existing_match=yes is retained in the observation release and excluded from Full50 training input"
)
supplement_atomic_json(manifest, manifest_path)
message(sprintf("02 complete: built %d-row observation release (%d training-eligible): %s", nrow(release), nrow(training), output_path))
