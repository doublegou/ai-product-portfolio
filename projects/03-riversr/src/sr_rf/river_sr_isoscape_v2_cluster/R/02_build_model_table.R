source("R/functions/core.R")
source("R/functions/predictor_sets.R")
check_packages(c("dplyr","readr"))
cfg <- read_config(); ensure_dirs(cfg)
obs <- read_observations()

pred_path <- file.path(project_root(), cfg$predictors$sample_file)
stop_missing(
  pred_path,
  paste0(
    "Create one row per row_id and save it as RDS.\n",
    "Use the template data/external/predictors_at_sites_TEMPLATE.csv.\n",
    "Predictor names must use prefixes p0__, p1__, p2a__, p2q__, p3__."
  )
)
pred <- readRDS(pred_path)
if (!"row_id" %in% names(pred)) stop("predictors_at_sites.rds must contain row_id.")
if (anyDuplicated(pred$row_id)) stop("predictors_at_sites.rds has duplicated row_id values.")

predictor_prefix_pattern <- "^(p0__|p1__|p2a__|p2q__|p3__)"

pred <- pred |>
  dplyr::select(
    row_id,
    dplyr::matches(predictor_prefix_pattern)
  )

model <- obs |>
  dplyr::left_join(pred, by="row_id")

sets <- resolve_predictor_sets(model, cfg)
set_summary <- dplyr::bind_rows(lapply(names(sets), function(nm) {
  tibble::tibble(
    predictor_set=nm,
    n_predictors=length(sets[[nm]]),
    complete_fraction=predictor_completeness(model, sets[[nm]]),
    variables=paste(sets[[nm]], collapse=";")
  )
}))
write_csv_safe(set_summary, file.path(project_root(),"outputs/qc/predictor_set_summary.csv"))

max_complete <- max(set_summary$complete_fraction)
if (max_complete < cfg$predictors$minimum_complete_fraction) {
  warning("Predictor completeness is low. Best complete fraction: ", round(max_complete,3))
}

group_path <- file.path(project_root(), cfg$predictors$group_file)
if (file.exists(group_path)) {
  groups <- readr::read_csv(group_path, show_col_types=FALSE)
  if (!"row_id" %in% names(groups)) stop("spatial_groups.csv must contain row_id.")
  model <- model |> dplyr::left_join(groups, by="row_id")
}

write_atomic_rds(model, file.path(project_root(),"data/processed/model_table.rds"))
log_msg("Model table written: ", nrow(model), " rows; ", ncol(model), " columns.")
