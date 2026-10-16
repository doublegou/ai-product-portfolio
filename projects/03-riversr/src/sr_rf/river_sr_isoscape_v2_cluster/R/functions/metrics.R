metric_row <- function(obs, pred, threshold = 0.720) {
  ok <- is.finite(obs) & is.finite(pred)
  obs <- obs[ok]; pred <- pred[ok]
  if (!length(obs)) return(tibble::tibble())
  err <- pred - obs
  q90 <- stats::quantile(obs, 0.90, na.rm=TRUE, names=FALSE)
  q95 <- stats::quantile(obs, 0.95, na.rm=TRUE, names=FALSE)
  high <- obs >= threshold
  slope <- tryCatch(stats::coef(stats::lm(obs ~ pred))[2], error=function(e) NA_real_)
  obs_range <- diff(range(obs, na.rm=TRUE))
  pred_range <- diff(range(pred, na.rm=TRUE))
  tibble::tibble(
    n = length(obs),
    rmse = sqrt(mean(err^2)),
    mae = mean(abs(err)),
    r2_sse = 1 - sum(err^2) / sum((obs - mean(obs))^2),
    bias = mean(err),
    top10_bias = mean(err[obs >= q90]),
    top05_bias = mean(err[obs >= q95]),
    high_n = sum(high),
    high_rmse = if (any(high)) sqrt(mean(err[high]^2)) else NA_real_,
    high_bias = if (any(high)) mean(err[high]) else NA_real_,
    predicted_range_ratio = if (obs_range > 0) pred_range / obs_range else NA_real_,
    calibration_slope = unname(slope),
    max_observed = max(obs),
    max_predicted = max(pred)
  )
}

select_params_guardrail <- function(metrics, tolerance = 0.05) {
  by_param <- metrics |>
    dplyr::group_by(param_id) |>
    dplyr::summarise(
      rmse = mean(rmse, na.rm=TRUE),
      high_bias = mean(high_bias, na.rm=TRUE),
      top05_bias = mean(top05_bias, na.rm=TRUE),
      range_ratio = mean(predicted_range_ratio, na.rm=TRUE),
      .groups="drop"
    )
  min_rmse <- min(by_param$rmse, na.rm=TRUE)
  eligible <- by_param |>
    dplyr::filter(rmse <= min_rmse * (1 + tolerance)) |>
    dplyr::mutate(
      tail_score = abs(high_bias) + abs(top05_bias) + abs(1 - pmin(range_ratio, 2))
    ) |>
    dplyr::arrange(tail_score, rmse)
  eligible$param_id[[1]]
}
