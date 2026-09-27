source("R/functions/core.R")
source("R/functions/qc.R")
check_packages(c("readxl","dplyr","readr","digest","stringr","ggplot2"))
cfg <- read_config(); ensure_dirs(cfg)

input <- file.path(project_root(), cfg$raw_data$workbook)
stop_missing(input)
log_msg("Reading ", input)
dat <- readxl::read_excel(input, sheet = cfg$raw_data$sheet, guess_max = 10000)

expected <- c(
  "sample_id","material_id","original_sample_id","original_material_id","location_name",
  "latitude","longitude","coordinates_type","short_references","material_type",
  "water_provenance","sample_type","sr87_sr86","sr87_sr86_uncertainty",
  "sr87_sr86_uncertainty_type","sr_concentration_ppm",
  "sr_concentration_ppm_uncertainty","sr_concentration_uncertainty_type",
  "dataset_doi","analytical_parameters_id","context"
)
missing_cols <- setdiff(expected, names(dat))
if (length(missing_cols)) stop("Workbook schema changed. Missing: ", paste(missing_cols, collapse=", "))

f <- cfg$raw_data$required_filters
dat <- dat |>
  dplyr::filter(
    material_type == f$material_type,
    water_provenance == f$water_provenance,
    sample_type == f$sample_type,
    context == f$context
  )

if (nrow(dat) != cfg$raw_data$expected_rows) {
  warning("Expected ", cfg$raw_data$expected_rows, " rows but read ", nrow(dat),
          ". Continue only after checking the source workbook.")
}

dat <- add_qc_flags(dat, cfg)
clean <- dat |>
  dplyr::filter(qc_keep_core)

write_atomic_rds(dat, file.path(project_root(),"data/processed/river_sr_observations_all_flags.rds"))
write_atomic_rds(clean, file.path(project_root(),"data/processed/river_sr_observations_clean.rds"))
write_csv_safe(dat, file.path(project_root(),"outputs/qc/observations_with_qc_flags.csv"))
write_csv_safe(make_qc_summary(dat), file.path(project_root(),"outputs/qc/qc_summary.csv"))

for (threshold in unlist(cfg$qc$diagnostic_thresholds)) {
  nm <- sprintf("tail_audit_ge_%.3f.csv", threshold)
  write_csv_safe(tail_audit(dat, threshold), file.path(project_root(),"outputs/qc",nm))
}

ref_summary <- dat |>
  dplyr::group_by(reference_id, short_references) |>
  dplyr::summarise(
    n=dplyr::n(), n_sites=dplyr::n_distinct(site_id),
    sr_min=min(sr87_sr86,na.rm=TRUE), sr_median=stats::median(sr87_sr86,na.rm=TRUE),
    sr_max=max(sr87_sr86,na.rm=TRUE),
    concentration_n=sum(!is.na(sr_concentration_ppm)),
    concentration_review_n=sum(flag_concentration_unit_review),
    .groups="drop"
  ) |>
  dplyr::arrange(dplyr::desc(n))
write_csv_safe(ref_summary, file.path(project_root(),"outputs/qc/reference_summary.csv"))

p1 <- ggplot2::ggplot(clean, ggplot2::aes(sr87_sr86)) +
  ggplot2::geom_histogram(bins=100) +
  ggplot2::geom_vline(xintercept=c(0.718,0.720,0.722), linetype=2) +
  ggplot2::labs(x="87Sr/86Sr", y="Count", title="River-water 87Sr/86Sr distribution")
ggplot2::ggsave(file.path(project_root(),"outputs/qc/sr_distribution.png"), p1, width=9, height=5, dpi=180)

p2 <- ggplot2::ggplot(clean, ggplot2::aes(longitude, latitude, colour=sr87_sr86)) +
  ggplot2::geom_point(size=0.7, alpha=0.75) +
  ggplot2::coord_quickmap() +
  ggplot2::labs(title="Raw observation coverage", colour="87Sr/86Sr")
ggplot2::ggsave(file.path(project_root(),"outputs/qc/raw_observation_map.png"), p2, width=11, height=6, dpi=180)

template <- clean |>
  dplyr::select(row_id, sample_id, site_id, reference_id, latitude, longitude) |>
  dplyr::mutate(
    p0__example_legacy_predictor = NA_real_,
    p1__local_bedrock_sr_median = NA_real_,
    p1__up_bedrock_sr_p90 = NA_real_,
    p2a__upstream_area_weighted_example = NA_real_,
    p2q__upstream_runoff_weighted_example = NA_real_,
    p3__baseflow_index = NA_real_
  )
write_csv_safe(template, file.path(project_root(),"data/external/predictors_at_samples_TEMPLATE.csv"))

log_msg("QC complete. Clean rows: ", nrow(clean))
log_msg("No duplicate rows were automatically removed.")
log_msg("Before experiment E2, verify concentration units and create data/external/CONCENTRATION_UNITS_VERIFIED.txt")
