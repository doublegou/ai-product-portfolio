risk_pr_auc <- function(truth, probability) {
  truth <- as.logical(truth)
  probability <- as.numeric(probability)
  valid <- !is.na(truth) & is.finite(probability)
  truth <- truth[valid]
  probability <- probability[valid]
  if (!any(truth) || all(truth)) return(NA_real_)
  as.numeric(PRROC::pr.curve(
    scores.class0 = probability[truth], scores.class1 = probability[!truth], curve = FALSE
  )$auc.integral)
}

risk_roc_auc <- function(truth, probability) {
  truth <- as.logical(truth)
  probability <- as.numeric(probability)
  valid <- !is.na(truth) & is.finite(probability)
  truth <- truth[valid]
  probability <- probability[valid]
  if (!any(truth) || all(truth)) return(NA_real_)
  as.numeric(pROC::auc(pROC::roc(truth, probability, levels = c(FALSE, TRUE), direction = "<", quiet = TRUE)))
}

risk_threshold_curve <- function(observed, probability, hydrological_group, context) {
  observed <- as.numeric(observed)
  probability <- as.numeric(probability)
  hydrological_group <- as.character(hydrological_group)
  risk_assert(length(observed) == length(probability) && length(observed) == length(hydrological_group), "Threshold inputs have different lengths.")
  risk_assert(all(is.finite(observed)) && all(is.finite(probability)), "Threshold inputs contain non-finite values.")
  positive <- observed >= as.numeric(context$config$target$positive_lower)
  background <- observed < as.numeric(context$config$target$background_upper)
  gray_zone <- observed >= as.numeric(context$config$target$background_upper) & observed < as.numeric(context$config$target$positive_lower)
  extreme <- observed >= as.numeric(context$config$target$extreme_lower)
  order_index <- order(-probability, seq_along(probability))
  p <- probability[order_index]
  positive <- positive[order_index]
  background <- background[order_index]
  gray_zone <- gray_zone[order_index]
  extreme <- extreme[order_index]
  groups <- hydrological_group[order_index]
  n <- length(p)
  total_positive <- sum(positive)
  total_background <- sum(background)
  total_gray <- sum(gray_zone)
  total_positive_groups <- length(unique(groups[positive]))
  total_extreme_groups <- length(unique(groups[extreme]))
  risk_assert(total_positive > 0L && total_background > 0L, "Threshold selection requires both positives and clear-background rows.")

  new_positive_group <- logical(n)
  positive_seen <- character()
  new_extreme_group <- logical(n)
  extreme_seen <- character()
  for (i in seq_len(n)) {
    if (positive[[i]] && !groups[[i]] %in% positive_seen) {
      new_positive_group[[i]] <- TRUE
      positive_seen <- c(positive_seen, groups[[i]])
    }
    if (extreme[[i]] && !groups[[i]] %in% extreme_seen) {
      new_extreme_group[[i]] <- TRUE
      extreme_seen <- c(extreme_seen, groups[[i]])
    }
  }
  cumulative_tp <- cumsum(positive)
  cumulative_background <- cumsum(background)
  cumulative_gray <- cumsum(gray_zone)
  cumulative_positive_groups <- cumsum(new_positive_group)
  cumulative_extreme_groups <- cumsum(new_extreme_group)
  ends <- which(!duplicated(p, fromLast = TRUE))
  no_trigger_threshold <- max(1 + .Machine$double.eps, max(p) + .Machine$double.eps)
  result <- data.frame(
    threshold = c(no_trigger_threshold, p[ends]),
    n_predicted_positive = c(0L, ends),
    true_positive = c(0L, cumulative_tp[ends]),
    recall = c(0, cumulative_tp[ends] / total_positive),
    precision = c(0, cumulative_tp[ends] / ends),
    precision_defined = c(FALSE, rep(TRUE, length(ends))),
    background_fpr = c(0, cumulative_background[ends] / total_background),
    gray_zone_trigger_rate = c(0, if (total_gray == 0L) rep(NA_real_, length(ends)) else cumulative_gray[ends] / total_gray),
    positive_groups_detected = c(0L, cumulative_positive_groups[ends]),
    positive_group_coverage = c(0, cumulative_positive_groups[ends] / total_positive_groups),
    extreme_groups_detected = c(0L, cumulative_extreme_groups[ends]),
    extreme_group_coverage = c(0, if (total_extreme_groups == 0L) rep(NA_real_, length(ends)) else cumulative_extreme_groups[ends] / total_extreme_groups),
    stringsAsFactors = FALSE
  )
  result
}

risk_metrics_from_triggers <- function(observed, probability, triggered, hydrological_group, context) {
  observed <- as.numeric(observed)
  probability <- as.numeric(probability)
  triggered <- as.logical(triggered)
  hydrological_group <- as.character(hydrological_group)
  positive <- observed >= as.numeric(context$config$target$positive_lower)
  background <- observed < as.numeric(context$config$target$background_upper)
  gray_zone <- observed >= as.numeric(context$config$target$background_upper) & observed < as.numeric(context$config$target$positive_lower)
  extreme <- observed >= as.numeric(context$config$target$extreme_lower)
  n_predicted <- sum(triggered)
  true_positive <- sum(triggered & positive)
  positive_groups <- unique(hydrological_group[positive])
  extreme_groups <- unique(hydrological_group[extreme])
  detected_positive_groups <- unique(hydrological_group[triggered & positive])
  detected_extreme_groups <- unique(hydrological_group[triggered & extreme])
  data.frame(
    n = length(observed), n_observed_positive = sum(positive), n_background = sum(background), n_gray_zone = sum(gray_zone),
    n_observed_extreme = sum(extreme), n_predicted_positive = n_predicted, true_positive = true_positive,
    recall = if (sum(positive) == 0L) 0 else true_positive / sum(positive),
    precision = if (n_predicted == 0L) 0 else true_positive / n_predicted,
    precision_defined = n_predicted > 0L,
    background_fpr = if (sum(background) == 0L) 0 else sum(triggered & background) / sum(background),
    gray_zone_trigger_rate = if (sum(gray_zone) == 0L) NA_real_ else sum(triggered & gray_zone) / sum(gray_zone),
    pr_auc = risk_pr_auc(positive, probability), roc_auc = risk_roc_auc(positive, probability),
    positive_groups_detected = length(detected_positive_groups),
    positive_groups_total = length(positive_groups),
    positive_group_coverage = if (length(positive_groups) == 0L) 0 else length(detected_positive_groups) / length(positive_groups),
    extreme_groups_detected = length(detected_extreme_groups),
    extreme_groups_total = length(extreme_groups),
    extreme_group_coverage = if (length(extreme_groups) == 0L) 0 else length(detected_extreme_groups) / length(extreme_groups),
    stringsAsFactors = FALSE
  )
}
