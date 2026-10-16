file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- supplement_context(script_path)

input_path <- supplement_path(context, context$config$input$raw)
output_path <- supplement_path(context, context$config$output$validated)
supplement_assert(file.exists(input_path), paste("Missing raw supplement:", input_path))

raw <- data.table::fread(input_path, encoding = "UTF-8", na.strings = c("", "NA"))
required <- c(
  "supplement_id", "source_dataset", "source_record_id", "location_name",
  "latitude", "longitude", "sample_date", "water_provenance", "sample_fraction",
  "sr87_sr86", "sr_band", "source_reference", "article_doi", "data_doi",
  "source_url", "license", "possible_existing_match", "notes"
)
missing <- setdiff(required, names(raw))
supplement_assert(length(missing) == 0L, paste("Raw supplement is missing columns:", paste(missing, collapse = ", ")))
supplement_assert(nrow(raw) == as.integer(context$config$contract$rows), "Raw supplement row count differs from the frozen contract.")
supplement_assert(!anyDuplicated(raw$supplement_id), "supplement_id is not unique.")
supplement_assert(all(is.finite(raw$latitude) & raw$latitude >= -90 & raw$latitude <= 90), "Invalid latitude found.")
supplement_assert(all(is.finite(raw$longitude) & raw$longitude >= -180 & raw$longitude <= 180), "Invalid longitude found.")
supplement_assert(all(is.finite(raw$sr87_sr86) & raw$sr87_sr86 > 0.69 & raw$sr87_sr86 < 1.30), "Invalid Sr ratio found.")
supplement_assert(all(nzchar(trimws(raw$source_url))), "A source URL is missing.")
supplement_assert(all(nzchar(trimws(raw$license))), "A license/status field is missing.")
supplement_assert(all(raw$possible_existing_match %in% c("yes", "no")), "possible_existing_match must be yes/no.")

source_counts <- table(raw$source_dataset)
expected_sources <- unlist(context$config$contract$source_rows)
expected_sources <- expected_sources[order(names(expected_sources))]
actual_sources <- source_counts[order(names(source_counts))]
supplement_assert(
  identical(names(actual_sources), names(expected_sources)) && identical(as.integer(actual_sources), as.integer(expected_sources)),
  "Source counts differ from the frozen contract."
)

computed_band <- as.character(supplement_band(raw$sr87_sr86))
supplement_assert(identical(computed_band, as.character(raw$sr_band)), "One or more stored Sr bands disagree with the numeric response.")
band_counts <- table(factor(computed_band, levels = names(context$config$contract$sr_bands)))
expected_bands <- unlist(context$config$contract$sr_bands)
supplement_assert(identical(as.integer(band_counts), as.integer(expected_bands)), "Sr-band counts differ from the frozen contract.")

possible_matches <- sum(raw$possible_existing_match == "yes")
supplement_assert(possible_matches == as.integer(context$config$contract$possible_existing_matches), "Possible-existing-match count differs from the contract.")

supplement_atomic_rds(raw, output_path)
message(sprintf("01 complete: validated %d rows from %d sources: %s", nrow(raw), length(source_counts), output_path))
