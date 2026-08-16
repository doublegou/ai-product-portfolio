file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

input_paths <- unlist(context$config$output[c(
  "candidate_sites", "basin_assignment", "hydrology", "geology",
  "climate_terrain", "soil", "geologic_age"
)], use.names = TRUE)
input_paths <- vapply(input_paths, function(path) river_sr_path(context, path), character(1L))
missing <- input_paths[!file.exists(input_paths)]
river_sr_assert(length(missing) == 0L, paste("Run steps 01-07 first; missing:", paste(missing, collapse = ", ")))

sites <- data.table::as.data.table(readRDS(input_paths[["candidate_sites"]]))
assignment <- data.table::as.data.table(readRDS(input_paths[["basin_assignment"]]))[, .(
  site_id,
  r47__current_hybas_id = current_hybas_id,
  r47__hybrid_hybas_id = hybrid_hybas_id,
  r47__hybas_source = hybas_source,
  r47__legacy_hybas_id = legacy_hybas_id
)]
read_features <- function(name) {
  x <- data.table::as.data.table(readRDS(input_paths[[name]]))
  keep <- c("site_id", grep("^(p0__|r47__|p1r__|local_geo_|up_geo_)", names(x), value = TRUE))
  keep <- setdiff(keep, c(
    "r47__current_hybas_id", "r47__legacy_hybas_id",
    "r47__hybrid_hybas_id", "r47__hybas_source"
  ))
  drop <- setdiff(names(x), keep)
  if (length(drop) > 0L) x[, (drop) := NULL]
  x
}
parts <- list(
  sites,
  assignment,
  read_features("hydrology"),
  read_features("geology"),
  read_features("climate_terrain"),
  read_features("soil"),
  read_features("geologic_age")
)
table <- Reduce(function(x, y) merge(x, y, by = "site_id", all.x = TRUE, sort = FALSE), parts)
river_sr_assert(nrow(table) == nrow(sites), "Feature joins changed the candidate-site count.")

lithologies <- c(
  "unconsolidated", "siliciclastic", "mixed_sedimentary", "carbonate",
  "metamorphic", "plutonic", "volcanic", "evaporite"
)
for (group in lithologies) {
  table[, (paste0("up_geo_", group, "_frac")) := get(paste0("p0__up_geo_", group, "_frac"))]
  table[, (paste0("r47__local_minus_up_geo_", group)) :=
    get(paste0("r47__local_geo_", group)) - get(paste0("p0__up_geo_", group, "_frac"))]
}

table[, `:=`(
  r47__local_radiogenic_crystalline_proxy = r47__local_geo_metamorphic + r47__local_geo_plutonic,
  r47__local_siliciclastic_source_proxy = r47__local_geo_siliciclastic + r47__local_geo_mixed_sedimentary,
  r50__local_radiogenic_crystalline = r47__local_geo_metamorphic + r47__local_geo_plutonic,
  r50__local_sedimentary_source = r47__local_geo_siliciclastic + r47__local_geo_mixed_sedimentary,
  r50__upstream_radiogenic_crystalline = up_geo_metamorphic_frac + up_geo_plutonic_frac,
  r50__upstream_sedimentary_source = up_geo_siliciclastic_frac + up_geo_mixed_sedimentary_frac,
  p1r__local_carbonate_evaporite_proxy = r47__local_geo_carbonate + r47__local_geo_evaporite,
  p1r__up_carbonate_evaporite_proxy = up_geo_carbonate_frac + up_geo_evaporite_frac,
  p1r__local_minus_up_soil_clay_pct_0_30cm = p1r__local_soil_clay_pct_0_30cm - p0__up_soil_clay_pct_0_30cm,
  p1r__local_minus_up_soil_pH_0_30cm = p1r__local_soil_pH_0_30cm - p1r__up_soil_pH_0_30cm,
  p1r__local_minus_up_elevation_m = p1r__local_elevation_m - p0__up_elevation_m
)]
table[, `:=`(
  r47__contrast_radiogenic_crystalline_proxy = r47__local_radiogenic_crystalline_proxy - r50__upstream_radiogenic_crystalline,
  r47__contrast_siliciclastic_source_proxy = r47__local_siliciclastic_source_proxy - r50__upstream_sedimentary_source,
  p1r__local_minus_up_carbonate_evaporite_proxy = p1r__local_carbonate_evaporite_proxy - p1r__up_carbonate_evaporite_proxy,
  p1r__carbonate_evaporite_proxy_x_aridity = p1r__up_carbonate_evaporite_proxy * p1r__local_ai_ratio,
  r50__local_composition_sum = rowSums(.SD)
), .SDcols = paste0("r47__local_geo_", lithologies)]
upstream_lithology_columns <- paste0("up_geo_", lithologies, "_frac")
table[, r50__upstream_composition_sum := rowSums(.SD), .SDcols = upstream_lithology_columns]

lithology_columns <- paste0("p0__up_geo_", lithologies, "_frac")
lith_matrix <- as.matrix(table[, ..lithology_columns])
lith_matrix <- lith_matrix / rowSums(lith_matrix)
table[, m1a__lith_entropy_norm := apply(lith_matrix, 1L, function(p) {
  p <- p[is.finite(p) & p > 0]
  if (length(p) == 0L) NA_real_ else -sum(p * log(p)) / log(length(lithologies))
})]

table[, `:=`(
  regime_carbonate_dominated = pmax(r47__local_geo_carbonate, up_geo_carbonate_frac) >= 0.50,
  regime_radiogenic_crystalline = pmax(r50__local_radiogenic_crystalline, r50__upstream_radiogenic_crystalline) >= 0.50 |
    pmax(local_geo_frac_midpoint_gt_2000, up_geo_frac_midpoint_gt_2000) >= 0.50,
  regime_volcanic_dominated = pmax(r47__local_geo_volcanic, up_geo_volcanic_frac) >= 0.50,
  regime_sedimentary_dominated = pmax(r50__local_sedimentary_source, r50__upstream_sedimentary_source) >= 0.50,
  regime_unconsolidated_dominated = pmax(r47__local_geo_unconsolidated, up_geo_unconsolidated_frac) >= 0.50,
  regime_evaporite_influenced = pmax(r47__local_geo_evaporite, up_geo_evaporite_frac) >= 0.05
)]
table[, regime_mixed_geology := !regime_carbonate_dominated & !regime_radiogenic_crystalline &
  !regime_volcanic_dominated & !regime_sedimentary_dominated &
  !regime_unconsolidated_dominated & !regime_evaporite_influenced]
table[, geological_regime_primary := data.table::fcase(
  regime_evaporite_influenced, "evaporite_influenced",
  regime_radiogenic_crystalline, "radiogenic_crystalline",
  regime_carbonate_dominated, "carbonate_dominated",
  regime_volcanic_dominated, "volcanic_dominated",
  regime_sedimentary_dominated, "sedimentary_dominated",
  regime_unconsolidated_dominated, "unconsolidated_dominated",
  default = "mixed_geology"
)]

# Step 03 leaves P0 hydrology missing when no reach is found within the
# configured snap distance; only forward-resolved sites enter the table.
table <- table[is.finite(p0__sp_x)]
table[, `:=`(row_id = site_id, sample_id = site_id)]
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
