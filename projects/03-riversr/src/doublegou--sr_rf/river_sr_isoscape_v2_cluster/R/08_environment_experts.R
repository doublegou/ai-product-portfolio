source("R/functions/core.R")
check_packages(c("dplyr","readr"))
cfg <- read_config(); ensure_dirs(cfg)
dat <- read_model_table()
col <- cfg$experts$hydrogeo_column
if (!col %in% names(dat)) {
  stop(
    "Experiment D requires a hydrogeological regime column named '", col, "'.\n",
    "Add it through data/external/spatial_groups.csv and rerun stages 02 onward.\n",
    "Suggested diagnostic regimes: radiogenic_orogenic, carbonate_evaporite, ",
    "young_volcanic, arid_saline, humid_weathered, glacial_permafrost."
  )
}
resid <- readRDS(file.path(project_root(),"outputs/diagnostics/best_global_oof_residuals.rds"))
diag <- resid |>
  dplyr::group_by(.data[[col]]) |>
  dplyr::summarise(
    n=dplyr::n(), n_sites=dplyr::n_distinct(site_id),
    n_references=dplyr::n_distinct(reference_id),
    mean_residual=mean(residual), median_residual=stats::median(residual),
    rmse=sqrt(mean(residual^2)), .groups="drop"
  ) |>
  dplyr::arrange(dplyr::desc(abs(mean_residual)))
write_csv_safe(diag,file.path(project_root(),"outputs/experiment_D/regime_residual_diagnostics.csv"))

eligible <- diag |>
  dplyr::filter(n >= cfg$experts$minimum_expert_rows, n_sites >= 20, n_references >= 3)
write_csv_safe(eligible,file.path(project_root(),"outputs/experiment_D/eligible_regimes.csv"))
log_msg("Experiment D diagnostic phase complete. Only eligible regimes should receive experts.")
log_msg("Expert fitting must use inner-spatial OOF residuals and be evaluated by leave-basin-out.")
