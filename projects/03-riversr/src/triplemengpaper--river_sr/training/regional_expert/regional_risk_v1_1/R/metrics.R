rrisk11_pr_auc <- function(truth, probability) {
  truth <- as.logical(truth); probability <- as.numeric(probability)
  if (!any(truth) || all(truth)) return(NA_real_)
  as.numeric(PRROC::pr.curve(scores.class0 = probability[truth], scores.class1 = probability[!truth], curve = FALSE)$auc.integral)
}

rrisk11_roc_auc <- function(truth, probability) {
  truth <- as.logical(truth); probability <- as.numeric(probability)
  if (!any(truth) || all(truth)) return(NA_real_)
  as.numeric(pROC::auc(pROC::roc(truth, probability, levels = c(FALSE, TRUE), direction = "<", quiet = TRUE)))
}

rrisk11_probability_metrics <- function(oof, probability_column, context) {
  probability <- rrisk11_clip_probability(oof[[probability_column]], as.numeric(context$config$model$probability_clip))
  truth <- as.integer(oof$high_sr_label); weight <- as.numeric(oof$branch_sqrt_weight)
  data.frame(
    probability_type = probability_column,
    weighted_brier = sum(weight * (probability - truth)^2) / sum(weight),
    weighted_log_loss = -sum(weight * (truth * log(probability) + (1 - truth) * log(1 - probability))) / sum(weight),
    pr_auc_station_equal = rrisk11_pr_auc(truth == 1L, probability),
    roc_auc_station_equal = rrisk11_roc_auc(truth == 1L, probability), stringsAsFactors = FALSE
  )
}

rrisk11_gate_metrics <- function(oof, operating_point, context) {
  trigger_column <- paste0("trigger_", operating_point)
  rrisk11_assert(trigger_column %in% names(oof), paste("Missing trigger column:", trigger_column))
  triggered <- as.logical(oof[[trigger_column]])
  observed <- as.numeric(oof$observed_sr); weight <- as.numeric(oof$branch_sqrt_weight)
  positive <- observed >= as.numeric(context$config$domain$positive_lower)
  background <- observed < as.numeric(context$config$domain$background_upper)
  gray <- !background & !positive
  extreme <- observed >= as.numeric(context$config$domain$extreme_lower)
  triggered_weight <- sum(weight * triggered)
  positive_branches <- unique(oof$regional_branch_id[positive]); extreme_branches <- unique(oof$regional_branch_id[extreme])
  detected_positive_branches <- unique(oof$regional_branch_id[triggered & positive])
  detected_extreme_branches <- unique(oof$regional_branch_id[triggered & extreme])
  data.frame(
    operating_point = operating_point, n = nrow(oof), n_triggered = sum(triggered),
    n_background = sum(background), n_background_triggered = sum(triggered & background),
    n_gray = sum(gray), n_gray_triggered = sum(triggered & gray),
    n_positive = sum(positive), n_positive_triggered = sum(triggered & positive),
    n_extreme = sum(extreme), n_extreme_triggered = sum(triggered & extreme),
    background_fpr = sum(weight * triggered * background) / sum(weight * background),
    recall = sum(weight * triggered * positive) / sum(weight * positive),
    precision = if (triggered_weight == 0) 0 else sum(weight * triggered * positive) / triggered_weight,
    gray_zone_trigger_rate = sum(weight * triggered * gray) / sum(weight * gray),
    extreme_recall = sum(weight * triggered * extreme) / sum(weight * extreme),
    positive_branches_detected = length(detected_positive_branches), positive_branches_total = length(positive_branches),
    positive_branch_coverage = length(detected_positive_branches) / length(positive_branches),
    extreme_branches_detected = length(detected_extreme_branches), extreme_branches_total = length(extreme_branches),
    extreme_branch_coverage = length(detected_extreme_branches) / length(extreme_branches), stringsAsFactors = FALSE
  )
}

rrisk11_branch_metrics <- function(oof, operating_point, context) {
  trigger_column <- paste0("trigger_", operating_point)
  do.call(rbind, lapply(split(oof, oof$regional_branch_id), function(x) {
    triggered <- as.logical(x[[trigger_column]]); observed <- as.numeric(x$observed_sr)
    positive <- observed >= as.numeric(context$config$domain$positive_lower)
    background <- observed < as.numeric(context$config$domain$background_upper)
    gray <- !background & !positive; extreme <- observed >= as.numeric(context$config$domain$extreme_lower)
    data.frame(
      operating_point = operating_point, regional_branch_id = x$regional_branch_id[[1L]], outer_fold = x$outer_fold[[1L]],
      n = nrow(x), n_triggered = sum(triggered), n_background = sum(background), n_background_triggered = sum(triggered & background),
      n_gray = sum(gray), n_gray_triggered = sum(triggered & gray), n_positive = sum(positive), n_positive_triggered = sum(triggered & positive),
      n_extreme = sum(extreme), n_extreme_triggered = sum(triggered & extreme),
      positive_branch_detected = any(triggered & positive), extreme_branch_detected = any(triggered & extreme), stringsAsFactors = FALSE
    )
  }))
}

rrisk11_apply_primary_targets <- function(metrics, context) {
  targets <- context$config$evidence_targets$primary
  metrics$pass_background_fpr <- metrics$background_fpr <= as.numeric(targets$max_background_fpr)
  metrics$pass_recall <- metrics$recall >= as.numeric(targets$min_recall)
  metrics$pass_precision <- metrics$precision >= as.numeric(targets$min_precision)
  metrics$pass_positive_branch_coverage <- metrics$positive_branch_coverage >= as.numeric(targets$min_positive_branch_coverage)
  metrics$pass_extreme_branch_coverage <- metrics$extreme_branch_coverage >= as.numeric(targets$min_extreme_branch_coverage)
  metrics$primary_gate_pass <- metrics$pass_background_fpr & metrics$pass_recall & metrics$pass_precision &
    metrics$pass_positive_branch_coverage & metrics$pass_extreme_branch_coverage
  metrics
}
