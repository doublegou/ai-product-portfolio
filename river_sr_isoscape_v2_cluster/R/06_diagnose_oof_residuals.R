source("R/functions/core.R")
source("R/functions/metrics.R")
check_packages(c("dplyr","readr","ggplot2"))
cfg <- read_config(); ensure_dirs(cfg)
dat <- read_model_table()
pred_path <- file.path(project_root(),"outputs/experiment_B/oof_predictions.rds")
stop_missing(pred_path, "Run experiment B first.")
pred <- readRDS(pred_path)

summary <- readr::read_csv(file.path(project_root(),"outputs/experiment_B/metrics_summary.csv"),
                           show_col_types=FALSE) |>
  dplyr::group_by(predictor_set,algorithm) |>
  dplyr::summarise(
    rmse=mean(rmse,na.rm=TRUE), high_bias=mean(high_bias,na.rm=TRUE),
    top05_bias=mean(top05_bias,na.rm=TRUE),
    range_ratio=mean(predicted_range_ratio,na.rm=TRUE), .groups="drop"
  ) |>
  dplyr::mutate(score=rank(rmse)+rank(abs(high_bias))+rank(abs(top05_bias))+rank(abs(1-range_ratio))) |>
  dplyr::arrange(score,rmse)
best <- summary[1,]
write_csv_safe(summary, file.path(project_root(),"outputs/diagnostics/global_model_ranking.csv"))

best_pred <- pred |>
  dplyr::filter(predictor_set==best$predictor_set, algorithm==best$algorithm) |>
  dplyr::group_by(row_id) |>
  dplyr::summarise(observed=dplyr::first(observed), predicted=mean(predicted), .groups="drop") |>
  dplyr::mutate(residual=observed-predicted) |>
  dplyr::left_join(dat, by="row_id")
write_atomic_rds(best_pred, file.path(project_root(),"outputs/diagnostics/best_global_oof_residuals.rds"))

groups <- c("reference_id","short_references","hydrogeo_regime","south_tibet_flag")
for (g in groups[groups %in% names(best_pred)]) {
  out <- best_pred |>
    dplyr::group_by(.data[[g]]) |>
    dplyr::summarise(n=dplyr::n(), n_high=sum(observed>=cfg$selection$high_threshold),
                     mean_residual=mean(residual), median_residual=stats::median(residual),
                     rmse=sqrt(mean(residual^2)), .groups="drop") |>
    dplyr::arrange(dplyr::desc(abs(mean_residual)))
  write_csv_safe(out, file.path(project_root(),"outputs/diagnostics",
                                paste0("residual_by_",safe_name(g),".csv")))
}

p <- ggplot2::ggplot(best_pred, ggplot2::aes(observed,predicted)) +
  ggplot2::geom_abline(slope=1,intercept=0,linetype=2) +
  ggplot2::geom_point(alpha=.5,size=.7) +
  ggplot2::labs(title=paste(best$algorithm,best$predictor_set),x="Observed",y="OOF predicted")
ggplot2::ggsave(file.path(project_root(),"outputs/diagnostics/best_oof_observed_predicted.png"),
                p,width=6,height=6,dpi=180)
log_msg("Residual diagnostics complete. Best candidate: ", best$algorithm, " / ", best$predictor_set)
