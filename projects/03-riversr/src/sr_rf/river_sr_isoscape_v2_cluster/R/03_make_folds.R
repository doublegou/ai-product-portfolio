source("R/functions/core.R")
source("R/functions/folds.R")
check_packages(c("sf","dplyr","readr"))
cfg <- read_config(); ensure_dirs(cfg)
dat <- read_model_table()

all_folds <- list()
for (km in unlist(cfg$folds$outer_block_sizes_km)) {
  fold <- make_spatial_folds(
    dat, km, cfg$folds$n_folds, cfg$folds$equal_area_crs,
    cfg$project$seed + km, cfg$selection$high_threshold
  ) |>
    dplyr::mutate(scheme=paste0("spatial_",km,"km"), block_size_km=km)
  all_folds[[length(all_folds)+1L]] <- fold
}
if (isTRUE(cfg$folds$include_reference_group_cv)) {
  fold <- make_reference_folds(dat, cfg$folds$n_folds, cfg$project$seed,
                               cfg$selection$high_threshold) |>
    dplyr::mutate(scheme="leave_reference_group_out", block_size_km=NA_real_)
  all_folds[[length(all_folds)+1L]] <- fold
}
folds <- dplyr::bind_rows(all_folds)
write_atomic_rds(folds, file.path(project_root(),"data/processed/folds_long.rds"))

summary <- folds |>
  dplyr::left_join(dat |> dplyr::select(row_id, sr87_sr86), by="row_id") |>
  dplyr::group_by(scheme, fold) |>
  dplyr::summarise(n=dplyr::n(), n_high=sum(sr87_sr86>=cfg$selection$high_threshold),
                   .groups="drop")
write_csv_safe(summary, file.path(project_root(),"outputs/folds/fold_balance.csv"))
log_msg("Fold schemes created: ", paste(unique(folds$scheme), collapse=", "))
