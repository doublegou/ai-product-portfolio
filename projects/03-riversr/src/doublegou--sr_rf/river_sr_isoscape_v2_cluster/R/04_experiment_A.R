source("R/functions/core.R")
source("R/functions/folds.R")
source("R/functions/metrics.R")
source("R/functions/modeling.R")
source("R/functions/predictor_sets.R")
check_packages(c("sf","dplyr","ranger","Cubist","xgboost","grf"))
cfg <- read_config(); ensure_dirs(cfg)
dat <- read_model_table()
folds_path <- file.path(project_root(),"data/processed/folds_long.rds")
stop_missing(folds_path, "Run stage 03.")
folds_all <- readRDS(folds_path)
sets <- resolve_predictor_sets(dat, cfg)

algorithms <- c("RF","Cubist")
all_pred <- list(); all_tune <- list(); all_metrics <- list()

for (scheme in unique(folds_all$scheme)) {
  fold <- folds_all |> dplyr::filter(scheme == !!scheme)
  for (set_name in names(sets)) {
    predictors <- sets[[set_name]]

    complete_index <- stats::complete.cases(
      dat[, predictors, drop = FALSE]
    )

    complete_fraction <- mean(complete_index)

    if (complete_fraction < cfg$predictors$minimum_complete_fraction) {
      log_msg(
        "Skipping ", scheme, " / ", set_name,
        ": low complete fraction (",
        round(complete_fraction, 3), ")."
      )
      next
    }

    dat_set <- dat[complete_index, , drop = FALSE]

    fold_set <- fold |>
      dplyr::filter(row_id %in% dat_set$row_id)

    log_msg(
      scheme, " / ", set_name,
      ": using ", nrow(dat_set),
      " complete rows and ",
      length(predictors), " predictors."
    )

    for (alg in algorithms) {
      res <- run_nested_cv(
        dat_set,
        fold_set,
        predictors,
        cfg$project$outcome,
        alg,
        cfg,
        seed = cfg$project$seed
      )
      pred <- res$predictions |>
        dplyr::mutate(scheme=scheme, predictor_set=set_name)
      met <- pred |>
        dplyr::group_by(scheme,predictor_set,algorithm,outer_fold) |>
        dplyr::group_modify(~metric_row(.x$observed,.x$predicted,cfg$selection$high_threshold)) |>
        dplyr::ungroup()
      all_pred[[length(all_pred)+1L]] <- pred
      all_tune[[length(all_tune)+1L]] <- res$tuning |>
        dplyr::mutate(scheme=scheme,predictor_set=set_name)
      all_metrics[[length(all_metrics)+1L]] <- met
      write_atomic_rds(dplyr::bind_rows(all_pred),
                       file.path(project_root(),"outputs/experiment_A/oof_predictions_partial.rds"))
    }
  }
}
pred <- dplyr::bind_rows(all_pred)
tune <- dplyr::bind_rows(all_tune)
metrics <- dplyr::bind_rows(all_metrics)
write_atomic_rds(pred, file.path(project_root(),"outputs/experiment_A/oof_predictions.rds"))
write_atomic_rds(tune, file.path(project_root(),"outputs/experiment_A/inner_tuning.rds"))
write_csv_safe(metrics, file.path(project_root(),"outputs/experiment_A/metrics_by_outer_fold.csv"))
summary <- metrics |>
  dplyr::group_by(scheme,predictor_set,algorithm) |>
  dplyr::summarise(dplyr::across(c(rmse,mae,r2_sse,bias,top10_bias,top05_bias,
                                   high_rmse,high_bias,predicted_range_ratio,
                                   calibration_slope,max_predicted),
                                 ~mean(.x,na.rm=TRUE)), .groups="drop")
write_csv_safe(summary, file.path(project_root(),"outputs/experiment_A/metrics_summary.csv"))
log_msg("Experiment A complete.")
