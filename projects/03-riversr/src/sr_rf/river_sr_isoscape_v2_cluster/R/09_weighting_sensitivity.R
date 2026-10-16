source("R/functions/core.R")
source("R/functions/metrics.R")
check_packages(c("dplyr","readr"))
cfg <- read_config(); ensure_dirs(cfg)
paths <- c(
  E0_area=file.path(project_root(),cfg$weighting$area_table),
  E1_runoff=file.path(project_root(),cfg$weighting$runoff_table)
)
missing <- paths[!file.exists(paths)]
if (length(missing)) {
  stop(
    "Experiment E requires separately built model tables.\nMissing:\n",
    paste(names(missing),missing,sep=" = ",collapse="\n"),
    "\nDo not mix area- and runoff-weighted predictors into one table."
  )
}
flux_flag <- file.path(project_root(),cfg$weighting$concentration_unit_audit_flag)
flux_path <- file.path(project_root(),cfg$weighting$sr_flux_table)
include_flux <- file.exists(flux_flag) && file.exists(flux_path)
if (file.exists(flux_path) && !file.exists(flux_flag)) {
  warning("Sr-flux table exists but is disabled because concentration units are not verified.")
}
manifest <- tibble::tibble(
  experiment=c(names(paths),if(include_flux)"E2_sr_flux" else character()),
  path=c(unname(paths),if(include_flux)flux_path else character()),
  enabled=TRUE
)
write_csv_safe(manifest,file.path(project_root(),"outputs/experiment_E/input_manifest.csv"))
log_msg("Weighting inputs validated. Run the same selected model/folds on each table.")
