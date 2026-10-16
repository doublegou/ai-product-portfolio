corr_basic_metrics <- function(observed, predicted) {
  observed <- as.numeric(observed); predicted <- as.numeric(predicted)
  corr_assert(length(observed) > 0L && length(observed) == length(predicted), "Metric vectors are empty or misaligned.")
  corr_assert(all(is.finite(observed)) && all(is.finite(predicted)), "Metrics received non-finite values.")
  error <- predicted - observed
  data.frame(n = length(observed), rmse = sqrt(mean(error^2)), station_mae = mean(abs(error)), bias = mean(error), stringsAsFactors = FALSE)
}

corr_group_metrics <- function(observed, predicted, groups) {
  frame <- data.frame(observed = as.numeric(observed), predicted = as.numeric(predicted), hydrological_group = as.character(groups), stringsAsFactors = FALSE)
  split_rows <- split(frame, frame$hydrological_group)
  records <- lapply(names(split_rows), function(group) {
    x <- split_rows[[group]]
    data.frame(hydrological_group = group, n = nrow(x), mae = mean(abs(x$predicted - x$observed)),
               bias = mean(x$predicted - x$observed), stringsAsFactors = FALSE)
  })
  result <- do.call(rbind, records)
  rownames(result) <- NULL
  result
}

corr_system_metrics <- function(observed, predicted, groups) {
  basic <- corr_basic_metrics(observed, predicted)
  group <- corr_group_metrics(observed, predicted, groups)
  cbind(basic, data.frame(n_groups = nrow(group), group_macro_mae = mean(group$mae), stringsAsFactors = FALSE))
}

corr_tail_label <- function(observed, context) {
  elevated <- as.numeric(context$config$oracle$elevated_lower)
  high <- as.numeric(context$config$oracle$high_lower)
  extreme <- as.numeric(context$config$oracle$extreme_lower)
  ifelse(observed >= elevated & observed < high, "0.72_to_0.75",
         ifelse(observed >= high & observed < extreme, "0.75_to_0.80",
                ifelse(observed >= extreme, "ge_0.80", NA_character_)))
}

corr_prediction_metrics <- function(frame, predicted_column, context) {
  oracle <- frame$oracle_elevated
  x <- frame[oracle, , drop = FALSE]
  metrics <- corr_system_metrics(x$observed, x[[predicted_column]], x$hydrological_group)
  correction <- if ("correction" %in% names(x)) x$correction else rep(0, nrow(x))
  cbind(metrics, data.frame(
    correction_trigger_rate = mean(correction > 0), correction_mean = mean(correction),
    correction_median = stats::median(correction), correction_p90 = unname(stats::quantile(correction, 0.90)),
    correction_p95 = unname(stats::quantile(correction, 0.95)), correction_max = max(correction),
    n_final_gt_1 = sum(x[[predicted_column]] > 1), fraction_final_gt_1 = mean(x[[predicted_column]] > 1),
    max_final_prediction = max(x[[predicted_column]]),
    n_above_outer_training_observed_max = if ("outer_training_observed_max" %in% names(x)) sum(x[[predicted_column]] > x$outer_training_observed_max) else NA_integer_,
    stringsAsFactors = FALSE
  ))
}

corr_tail_metrics <- function(frame, predicted_column, context) {
  x <- frame[frame$oracle_elevated, , drop = FALSE]
  x$tail_bin <- corr_tail_label(x$observed, context)
  records <- lapply(unlist(context$config$oracle$tail_bins), function(bin) {
    y <- x[x$tail_bin == bin, , drop = FALSE]
    corr_assert(nrow(y) > 0L, paste("Empty frozen tail bin:", bin))
    metrics <- corr_system_metrics(y$observed, y[[predicted_column]], y$hydrological_group)
    correction <- if ("correction" %in% names(y)) y$correction else rep(0, nrow(y))
    cbind(data.frame(tail_bin = bin, stringsAsFactors = FALSE), metrics,
          data.frame(correction_mean = mean(correction), correction_p90 = unname(stats::quantile(correction, 0.90)),
                     correction_max = max(correction), stringsAsFactors = FALSE))
  })
  do.call(rbind, records)
}
