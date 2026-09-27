rrisk2_pr_auc <- function(truth, probability) {
  truth <- as.logical(truth); if (!any(truth) || all(truth)) return(NA_real_)
  as.numeric(PRROC::pr.curve(scores.class0 = probability[truth], scores.class1 = probability[!truth], curve = FALSE)$auc.integral)
}

rrisk2_roc_auc <- function(truth, probability) {
  truth <- as.logical(truth); if (!any(truth) || all(truth)) return(NA_real_)
  as.numeric(pROC::auc(pROC::roc(truth, probability, levels = c(FALSE, TRUE), direction = "<", quiet = TRUE)))
}

rrisk2_probability_metrics <- function(oof, context) {
  p <- pmin(1 - as.numeric(context$config$model$probability_clip), pmax(as.numeric(context$config$model$probability_clip), as.numeric(oof$probability)))
  y <- as.integer(oof$high_sr_label); w <- as.numeric(oof$branch_sqrt_weight)
  data.frame(weighted_brier = sum(w * (p - y)^2) / sum(w), weighted_log_loss = -sum(w * (y * log(p) + (1-y) * log(1-p))) / sum(w),
             ap_station_equal = rrisk2_pr_auc(y == 1L, p), auroc_station_equal = rrisk2_roc_auc(y == 1L, p), stringsAsFactors = FALSE)
}

rrisk2_gate_metrics <- function(oof, context) {
  trigger <- as.logical(oof$trigger); observed <- as.numeric(oof$observed_sr); w <- as.numeric(oof$branch_sqrt_weight)
  positive <- observed >= as.numeric(context$config$domain$positive_lower); background <- observed < as.numeric(context$config$domain$background_upper)
  gray <- !positive & !background; extreme <- observed >= as.numeric(context$config$domain$extreme_lower); triggered_weight <- sum(w * trigger)
  pos_branches <- unique(oof$regional_branch_id[positive]); ex_branches <- unique(oof$regional_branch_id[extreme])
  pos_hit <- unique(oof$regional_branch_id[trigger & positive]); ex_hit <- unique(oof$regional_branch_id[trigger & extreme])
  data.frame(n = nrow(oof), n_triggered = sum(trigger), n_background = sum(background), n_background_triggered = sum(trigger & background),
    n_gray = sum(gray), n_gray_triggered = sum(trigger & gray), n_positive = sum(positive), n_positive_triggered = sum(trigger & positive),
    n_extreme = sum(extreme), n_extreme_triggered = sum(trigger & extreme),
    background_fpr = sum(w * trigger * background) / sum(w * background), recall = sum(w * trigger * positive) / sum(w * positive),
    precision = if (triggered_weight == 0) 0 else sum(w * trigger * positive) / triggered_weight,
    gray_zone_trigger_rate = sum(w * trigger * gray) / sum(w * gray), extreme_recall = sum(w * trigger * extreme) / sum(w * extreme),
    positive_branches_detected = length(pos_hit), positive_branches_total = length(pos_branches),
    extreme_branches_detected = length(ex_hit), extreme_branches_total = length(ex_branches), stringsAsFactors = FALSE)
}

rrisk2_apply_gate <- function(x, context) {
  target <- context$config$evidence_targets
  x$pass_background_fpr <- x$background_fpr <= as.numeric(target$max_background_fpr)
  x$pass_recall <- x$recall >= as.numeric(target$min_recall)
  x$pass_precision <- x$precision >= as.numeric(target$min_precision)
  x$pass_positive_branches <- x$positive_branches_detected >= as.integer(target$min_positive_branches_detected)
  x$pass_extreme_branches <- x$extreme_branches_detected >= as.integer(target$min_extreme_branches_detected)
  x$gate_pass <- x$pass_background_fpr & x$pass_recall & x$pass_precision & x$pass_positive_branches & x$pass_extreme_branches
  x
}

rrisk2_branch_metrics <- function(oof, context) do.call(rbind, lapply(split(oof, oof$regional_branch_id), function(x) {
  observed <- x$observed_sr; positive <- observed >= as.numeric(context$config$domain$positive_lower); extreme <- observed >= as.numeric(context$config$domain$extreme_lower)
  data.frame(regional_branch_id = x$regional_branch_id[1], outer_fold = x$outer_fold[1], n = nrow(x), n_triggered = sum(x$trigger),
    positive_station_n = sum(positive), high_hit_n = sum(x$trigger & positive), extreme_station_n = sum(extreme), extreme_hit_n = sum(x$trigger & extreme),
    branch_detected = any(x$trigger & positive), extreme_system_detected = any(x$trigger & extreme), stringsAsFactors = FALSE)
}))
