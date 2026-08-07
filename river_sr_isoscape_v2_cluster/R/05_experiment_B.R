source("R/functions/core.R")
source("R/functions/folds.R")
source("R/functions/metrics.R")
source("R/functions/modeling.R")
source("R/functions/predictor_sets.R")
check_packages(c("sf","dplyr","ranger","Cubist","xgboost","grf"))
cfg <- read_config(); ensure_dirs(cfg)
dat <- read_model_table()
folds_all <- readRDS(file.path(project_root(),"data/processed/folds_long.rds"))
sets <- resolve_predictor_sets(dat, cfg)

a_path <- file.path(project_root(),"outputs/experiment_A/metrics_summary.csv")
stop_missing(a_path, "Run experiment A first.")
a <- readr::read_csv(a_path, show_col_types=FALSE)

ranked <- a |>
  dplyr::group_by(predictor_set) |>
  dplyr::summarise(
    rmse=mean(rmse,na.rm=TRUE),
    high_bias=mean(high_bias,na.rm=TRUE),
    top05_bias=mean(top05_bias,na.rm=TRUE),
    range_ratio=mean(predicted_range_ratio,na.rm=TRUE),
    .groups="drop"
  ) |>
  dplyr::mutate(
    score=rank(rmse)+rank(abs(high_bias))+rank(abs(top05_bias))+rank(abs(1-range_ratio))
  ) |>
  dplyr::arrange(score,rmse)
selected <- intersect(head(ranked$predictor_set,2), names(sets))
write_csv_safe(ranked, file.path(project_root(),"outputs/experiment_B/predictor_set_ranking.csv"))
log_msg("Selected predictor sets: ", paste(selected, collapse=", "))

algorithms <- c("RF","Cubist","XGBoost","LLF")
all_pred <- list(); all_tune <- list(); all_metrics <- list()

for (scheme in unique(folds_all$scheme)) {
  fold <- folds_all |> dplyr::filter(scheme == !!scheme)
  for (set_name in selected) {
    predictors <- sets[[set_name]]
    for (alg in algorithms) {
      res <- run_nested_cv(dat, fold, predictors, cfg$project$outcome, alg, cfg,
                           seed=cfg$project$seed+10000)
      pred <- res$predictions |>
        dplyr::mutate(scheme=scheme,predictor_set=set_name)
      met <- pred |>
        dplyr::group_by(scheme,predictor_set,algorithm,outer_fold) |>
        dplyr::group_modify(~metric_row(.x$observed,.x$predicted,cfg$selection$high_threshold)) |>
        dplyr::ungroup()
      all_pred[[length(all_pred)+1L]] <- pred
      all_tune[[length(all_tune)+1L]] <- res$tuning |>
        dplyr::mutate(scheme=scheme,predictor_set=set_name)
      all_metrics[[length(all_metrics)+1L]] <- met
      write_atomic_rds(dplyr::bind_rows(all_pred),
                       file.path(project_root(),"outputs/experiment_B/oof_predictions_partial.rds"))
    }
  }
}
pred <- dplyr::bind_rows(all_pred)
metrics <- dplyr::bind_rows(all_metrics)
write_atomic_rds(pred, file.path(project_root(),"outputs/experiment_B/oof_predictions.rds"))
write_atomic_rds(dplyr::bind_rows(all_tune), file.path(project_root(),"outputs/experiment_B/inner_tuning.rds"))
write_csv_safe(metrics, file.path(project_root(),"outputs/experiment_B/metrics_by_outer_fold.csv"))
summary <- metrics |>
  dplyr::group_by(scheme,predictor_set,algorithm) |>
  dplyr::summarise(dplyr::across(c(rmse,mae,r2_sse,bias,top10_bias,top05_bias,
                                   high_rmse,high_bias,predicted_range_ratio,
                                   calibration_slope,max_predicted),
                                 ~mean(.x,na.rm=TRUE)), .groups="drop")
write_csv_safe(summary, file.path(project_root(),"outputs/experiment_B/metrics_summary.csv"))
log_msg("Experiment B complete.")
