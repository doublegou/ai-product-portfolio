file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

site_path <- river_sr_path(context, context$config$output$candidate_sites)
predictor_input_path <- river_sr_path(context, context$config$input$recovered_predictors)
river_sr_assert(file.exists(site_path), paste("Run step 01 first; missing:", site_path))
river_sr_assert(file.exists(predictor_input_path), paste("Missing recovered predictor input:", predictor_input_path))

sites <- data.table::as.data.table(readRDS(site_path))
recovered <- data.table::fread(predictor_input_path, encoding = "UTF-8", na.strings = c("", "NA"))
river_sr_assert(!anyDuplicated(sites$site_id), "Candidate sites contain duplicated site IDs.")
river_sr_assert(!anyDuplicated(recovered$site_id), "Recovered predictors contain duplicated site IDs.")
river_sr_assert(setequal(sites$site_id, recovered$site_id), "Candidate sites and recovered predictors do not have the same 4,527-site universe.")

table <- merge(sites, recovered, by = "site_id", all = FALSE, sort = FALSE)
river_sr_assert(nrow(table) == nrow(sites), "Recovered predictor join changed the candidate-site count.")

# The legacy CSV escaped non-ASCII reference characters as literal <U+XXXX>
# tokens. Reproduce that representation so the release is value-compatible in
# every metadata column as well as in the model variables.
escape_non_ascii <- function(values) {
  vapply(values, function(value) {
    if (is.na(value)) return(NA_character_)
    codepoints <- utf8ToInt(enc2utf8(value))
    paste0(vapply(codepoints, function(codepoint) {
      if (codepoint <= 127L) intToUtf8(codepoint) else sprintf("<U+%04X>", codepoint)
    }, character(1L)), collapse = "")
  }, character(1L), USE.NAMES = FALSE)
}
table[, `:=`(
  short_references = escape_non_ascii(short_references),
  references = escape_non_ascii(references)
)]

# The recovered snapshot contains 42 candidate sites that failed the original
# complete-P0 rule. Keeping that rule gives the historical 4,485-row V1.
table <- table[is.finite(p0__sp_x)]
predictors <- readLines(file.path(context$project_dir, "config", "full50_predictors.txt"), warn = FALSE)
predictors <- predictors[nzchar(trimws(predictors))]
river_sr_assert(length(predictors) == context$config$contract$full50_predictors, "Full50 manifest must contain 50 predictors.")
missing_predictors <- setdiff(predictors, names(table))
river_sr_assert(length(missing_predictors) == 0L, paste("Missing Full50 predictors:", paste(missing_predictors, collapse = ", ")))

output_columns <- c(
  "row_id", "site_id", "longitude", "latitude", "sr87_sr86",
  "r47__current_hybas_id", "r47__hybrid_hybas_id", "r47__hybas_source",
  "sample_id", "reference_id", "short_references", "sr_mean", "sr_sd", "sr_iqr", "sr_min", "sr_max",
  "n_unique_measurements", "n_references", "reference_ids", "references", "n_rows_original",
  "n_removed_as_duplicate", "sr_median_all_rows", "median_difference", "duplicate_sensitive_flag", "qc_keep_core",
  "r47__legacy_hybas_id",
  "r47__local_minus_up_geo_unconsolidated", "r47__local_minus_up_geo_siliciclastic",
  "r47__local_geo_mixed_sedimentary", "r47__local_minus_up_geo_mixed_sedimentary",
  "r47__local_minus_up_geo_carbonate", "r47__local_minus_up_geo_metamorphic",
  "r47__local_minus_up_geo_plutonic", "r47__local_minus_up_geo_volcanic", "r47__local_minus_up_geo_evaporite",
  "r47__local_radiogenic_crystalline_proxy", "r47__contrast_radiogenic_crystalline_proxy",
  "r47__local_siliciclastic_source_proxy", "r47__contrast_siliciclastic_source_proxy",
  paste0("up_geo_", c("carbonate", "evaporite", "metamorphic", "mixed_sedimentary", "plutonic", "siliciclastic", "unconsolidated", "volcanic"), "_frac"),
  "local_geo_age_resolved_coverage", "up_geo_age_resolved_coverage",
  "p1r__carbonate_evaporite_proxy_x_aridity", "p1r__local_carbonate_evaporite_proxy",
  "p1r__local_minus_up_carbonate_evaporite_proxy", "p1r__up_carbonate_evaporite_proxy",
  "p1r__local_minus_up_soil_clay_pct_0_30cm", "p1r__local_minus_up_soil_pH_0_30cm", "p1r__local_minus_up_elevation_m",
  "r50__upstream_radiogenic_crystalline", "r50__upstream_sedimentary_source",
  "r50__local_composition_sum", "r50__upstream_composition_sum",
  "regime_carbonate_dominated", "regime_radiogenic_crystalline", "regime_volcanic_dominated",
  "regime_sedimentary_dominated", "regime_unconsolidated_dominated", "regime_evaporite_influenced",
  "regime_mixed_geology", "geological_regime_primary",
  predictors,
  "r50__local_radiogenic_crystalline", "r50__local_sedimentary_source"
)
river_sr_assert(length(setdiff(output_columns, names(table))) == 0L, "One or more required output columns were not assembled.")
table <- table[, ..output_columns]
data.table::setorder(table, site_id)

river_sr_save_rds(table, river_sr_path(context, context$config$output$full50))
river_sr_write_csv(table, river_sr_path(context, context$config$output$processed))
message(sprintf("08 complete: %d x %d Full50 training table written to %s", nrow(table), ncol(table), river_sr_path(context, context$config$output$processed)))
