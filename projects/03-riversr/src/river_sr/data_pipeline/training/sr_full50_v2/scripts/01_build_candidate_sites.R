file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

base_path <- river_sr_path(context, context$config$input$observation_base)
supplement_path <- river_sr_path(context, context$config$input$observation_supplement)
output_path <- river_sr_path(context, context$config$output$candidate_sites)
river_sr_assert(file.exists(base_path), paste("Missing base observations:", base_path))
river_sr_assert(file.exists(supplement_path), paste("Missing supplement release:", supplement_path))

base <- data.table::fread(base_path, encoding = "UTF-8", na.strings = c("", "NA"))
supplement <- data.table::fread(supplement_path, encoding = "UTF-8", na.strings = c("", "NA"))
river_sr_assert(nrow(supplement) == as.integer(context$config$contract$supplement_observation_rows), "Supplement release row count differs from the contract.")
river_sr_assert("qc_include_training" %in% names(supplement), "Supplement release lacks qc_include_training.")
supplement <- supplement[qc_include_training == TRUE]
river_sr_assert(nrow(supplement) == as.integer(context$config$contract$supplement_training_rows), "Training-eligible supplement count differs from the contract.")

base[, `:=`(observation_release = "sr_full50_v1", source_dataset = NA_character_)]
supplement[, observation_release := "sr_supplement_v1"]
observations <- data.table::rbindlist(list(base, supplement), use.names = TRUE, fill = TRUE)

required_columns <- c(
  "sample_id", "material_id", "original_sample_id", "original_material_id",
  "latitude", "longitude", "short_references", "sr87_sr86",
  "sr87_sr86_uncertainty", "sr87_sr86_uncertainty_type",
  "sr_concentration_ppm", "sr_concentration_ppm_uncertainty",
  "sr_concentration_uncertainty_type", "dataset_doi",
  "analytical_parameters_id", "observation_release", "source_dataset"
)
missing_columns <- setdiff(required_columns, names(observations))
river_sr_assert(length(missing_columns) == 0L, paste("Observations are missing columns:", paste(missing_columns, collapse = ", ")))
river_sr_assert(!anyNA(observations$latitude) && !anyNA(observations$longitude), "Observations contain missing coordinates.")
river_sr_assert(all(is.finite(observations$sr87_sr86)), "Observations contain non-finite Sr ratios.")

coordinate_digits <- as.integer(context$config$rules$coordinate_digits)
observations[, site_id := river_sr_site_id(latitude, longitude, coordinate_digits)]
base_sites <- unique(observations[observation_release == "sr_full50_v1", site_id])
supplement_sites <- unique(observations[observation_release == "sr_supplement_v1", site_id])
river_sr_assert(length(intersect(base_sites, supplement_sites)) == 0L, "A training-eligible supplement site overlaps a base coordinate site.")

measurement_key <- c(
  "original_sample_id", "original_material_id", "latitude", "longitude",
  "short_references", "sr87_sr86", "sr87_sr86_uncertainty",
  "sr87_sr86_uncertainty_type", "sr_concentration_ppm",
  "sr_concentration_ppm_uncertainty", "sr_concentration_uncertainty_type",
  "dataset_doi", "analytical_parameters_id"
)
unique_measurements <- observations[!duplicated(observations, by = measurement_key)]
retained_key <- c(
  "sample_id", "material_id",
  setdiff(measurement_key, c("original_sample_id", "original_material_id", "analytical_parameters_id"))
)
unique_measurements <- unique_measurements[!duplicated(unique_measurements, by = retained_key)]

measurement_summary <- unique_measurements[, .(
  sr87_sr86 = stats::median(sr87_sr86, na.rm = TRUE),
  n_unique_measurements = .N
), by = site_id]

site_summary <- observations[, {
  refs <- sort(unique(trimws(short_references[!is.na(short_references)])))
  refs <- refs[nzchar(refs)]
  ref_ids <- sort(unique(river_sr_reference_id(refs)))
  ref_ids <- ref_ids[nzchar(ref_ids)]
  releases <- sort(unique(observation_release[!is.na(observation_release)]))
  datasets <- sort(unique(source_dataset[!is.na(source_dataset)]))
  datasets <- datasets[nzchar(datasets)]
  list(
    longitude = longitude[1L],
    latitude = latitude[1L],
    reference_id = if (length(refs) > 1L) {
      paste0("multi_reference_site__", site_id[1L])
    } else if (length(ref_ids) == 1L) {
      ref_ids
    } else {
      NA_character_
    },
    short_references = paste(refs, collapse = ";"),
    n_references = length(refs),
    reference_ids = paste(ref_ids, collapse = ";"),
    references = paste(refs, collapse = ";"),
    observation_releases = paste(releases, collapse = ";"),
    source_datasets = paste(datasets, collapse = ";"),
    is_supplemental_site = identical(releases, "sr_supplement_v1"),
    n_rows_original = .N,
    sr_median_all_rows = stats::median(sr87_sr86, na.rm = TRUE)
  )
}, by = site_id]

candidate_sites <- merge(site_summary, measurement_summary, by = "site_id", sort = FALSE)
candidate_sites[, `:=`(
  row_id = site_id,
  sample_id = site_id,
  sr_mean = sr87_sr86,
  sr_sd = as.numeric(NA),
  sr_iqr = 0,
  sr_min = sr87_sr86,
  sr_max = sr87_sr86,
  n_removed_as_duplicate = n_rows_original - n_unique_measurements,
  median_difference = sr87_sr86 - sr_median_all_rows,
  duplicate_sensitive_flag = abs(sr87_sr86 - sr_median_all_rows) >= 1e-4,
  qc_keep_core = TRUE
)]
data.table::setorder(candidate_sites, site_id)

river_sr_assert(!anyDuplicated(candidate_sites$site_id), "Candidate site IDs are not unique.")
river_sr_assert(nrow(candidate_sites) == as.integer(context$config$contract$candidate_sites), "Candidate site count differs from the frozen contract.")
river_sr_assert(sum(candidate_sites$is_supplemental_site) == 1122L, "Supplement candidate-site count differs from the frozen contract.")

river_sr_save_rds(candidate_sites, output_path)
message(sprintf(
  "01 complete: %d combined observations -> %d candidate sites (%d supplemental): %s",
  nrow(observations), nrow(candidate_sites), sum(candidate_sites$is_supplemental_site), output_path
))
