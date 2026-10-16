v1_calculate_metrics <- function(observed, predicted) {
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  valid <- is.finite(observed) & is.finite(predicted)
  observed <- observed[valid]
  predicted <- predicted[valid]
  n <- length(observed)
  if (n == 0L) {
    return(data.frame(
      n = 0L, rmse = NA_real_, mae = NA_real_, r2 = NA_real_, bias = NA_real_,
      calibration_intercept = NA_real_, calibration_slope = NA_real_,
      observed_min = NA_real_, observed_max = NA_real_, predicted_min = NA_real_, predicted_max = NA_real_
    ))
  }
  residual <- predicted - observed
  denominator <- sum((observed - mean(observed))^2)
  calibration <- if (length(unique(predicted)) > 1L) stats::coef(stats::lm(observed ~ predicted)) else c(NA_real_, NA_real_)
  data.frame(
    n = n,
    rmse = sqrt(mean(residual^2)),
    mae = mean(abs(residual)),
    r2 = if (denominator <= 0) NA_real_ else 1 - sum(residual^2) / denominator,
    bias = mean(residual),
    calibration_intercept = unname(calibration[[1L]]),
    calibration_slope = unname(calibration[[2L]]),
    observed_min = min(observed),
    observed_max = max(observed),
    predicted_min = min(predicted),
    predicted_max = max(predicted)
  )
}

v1_tail_bin <- function(observed) {
  cut(
    observed,
    breaks = c(-Inf, 0.72, 0.75, 0.80, Inf),
    right = FALSE,
    labels = c("lt_0.72", "0.72_to_0.75", "0.75_to_0.80", "ge_0.80")
  )
}

v1_tail_metrics <- function(predictions, prefix = NULL) {
  predictions$sr_bin <- v1_tail_bin(predictions$observed)
  bins <- levels(predictions$sr_bin)
  result <- do.call(rbind, lapply(bins, function(bin) {
    current <- predictions[predictions$sr_bin == bin, , drop = FALSE]
    cbind(data.frame(sr_bin = bin), v1_calculate_metrics(current$observed, current$predicted))
  }))
  if (!is.null(prefix)) result$evaluation <- prefix
  result
}

v1_threshold_metrics <- function(predictions, prefix = NULL) {
  thresholds <- c(0.72, 0.75, 0.80)
  result <- do.call(rbind, lapply(thresholds, function(threshold) {
    positive <- predictions$observed >= threshold
    current <- predictions[positive, , drop = FALSE]
    base <- v1_calculate_metrics(current$observed, current$predicted)
    data.frame(
      threshold = threshold,
      n_observed_positive = sum(positive),
      n_predicted_positive = sum(predictions$predicted >= threshold),
      recall_at_same_threshold = if (sum(positive) == 0L) NA_real_ else mean(predictions$predicted[positive] >= threshold),
      rmse = base$rmse,
      mae = base$mae,
      bias = base$bias,
      predicted_min = base$predicted_min,
      predicted_max = base$predicted_max
    )
  }))
  if (!is.null(prefix)) result$evaluation <- prefix
  result
}

v1_rank_summaries <- function(summary) {
  summary <- summary[order(
    summary$pooled_rmse,
    summary$pooled_mae,
    abs(summary$pooled_bias),
    -summary$pooled_r2,
    summary$mtry,
    summary$min_node_size,
    summary$sample_fraction,
    summary$replace
  ), , drop = FALSE]
  rownames(summary) <- NULL
  summary$tuning_rank <- seq_len(nrow(summary))
  summary
}
