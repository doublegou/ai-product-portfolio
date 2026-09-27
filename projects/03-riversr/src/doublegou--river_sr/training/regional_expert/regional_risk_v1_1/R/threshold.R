rrisk11_threshold_curve <- function(observed, probability, branch_id, weight, context) {
  observed <- as.numeric(observed); probability <- as.numeric(probability)
  branch_id <- as.character(branch_id); weight <- as.numeric(weight)
  n <- length(observed)
  rrisk11_assert(length(probability) == n && length(branch_id) == n && length(weight) == n, "Threshold inputs have different lengths.")
  rrisk11_assert(all(is.finite(observed)) && all(is.finite(probability)) && all(is.finite(weight)) && all(weight > 0), "Threshold inputs are invalid.")
  positive <- observed >= as.numeric(context$config$domain$positive_lower)
  background <- observed < as.numeric(context$config$domain$background_upper)
  gray <- !background & !positive
  extreme <- observed >= as.numeric(context$config$domain$extreme_lower)
  rrisk11_assert(any(positive) && any(background), "Threshold selection requires positive and clear-background rows.")

  order_index <- order(-probability, seq_along(probability))
  p <- probability[order_index]; w <- weight[order_index]
  positive <- positive[order_index]; background <- background[order_index]; gray <- gray[order_index]; extreme <- extreme[order_index]
  branch_id <- branch_id[order_index]
  ends <- which(!duplicated(p, fromLast = TRUE))
  cumulative_total_weight <- cumsum(w)
  cumulative_positive_weight <- cumsum(w * positive)
  cumulative_background_weight <- cumsum(w * background)
  cumulative_gray_weight <- cumsum(w * gray)
  cumulative_extreme_weight <- cumsum(w * extreme)
  total_positive_weight <- sum(w * positive)
  total_background_weight <- sum(w * background)
  total_gray_weight <- sum(w * gray)
  total_extreme_weight <- sum(w * extreme)
  positive_branches <- unique(branch_id[positive])
  extreme_branches <- unique(branch_id[extreme])
  detected_count <- function(end, mask) length(unique(branch_id[seq_len(end)][mask[seq_len(end)]]))
  positive_branch_detected <- vapply(ends, detected_count, integer(1L), mask = positive)
  extreme_branch_detected <- vapply(ends, detected_count, integer(1L), mask = extreme)
  no_trigger_threshold <- max(1 + .Machine$double.eps, max(p) + .Machine$double.eps)
  data.frame(
    threshold = c(no_trigger_threshold, p[ends]), n_triggered = c(0L, ends),
    recall = c(0, cumulative_positive_weight[ends] / total_positive_weight),
    precision = c(0, cumulative_positive_weight[ends] / cumulative_total_weight[ends]),
    background_fpr = c(0, cumulative_background_weight[ends] / total_background_weight),
    gray_zone_trigger_rate = c(0, if (total_gray_weight > 0) cumulative_gray_weight[ends] / total_gray_weight else rep(NA_real_, length(ends))),
    extreme_recall = c(0, if (total_extreme_weight > 0) cumulative_extreme_weight[ends] / total_extreme_weight else rep(NA_real_, length(ends))),
    positive_branches_detected = c(0L, positive_branch_detected),
    positive_branch_coverage = c(0, positive_branch_detected / length(positive_branches)),
    extreme_branches_detected = c(0L, extreme_branch_detected),
    extreme_branch_coverage = c(0, extreme_branch_detected / length(extreme_branches)),
    is_no_trigger = c(TRUE, rep(FALSE, length(ends))), stringsAsFactors = FALSE
  )
}

rrisk11_select_threshold <- function(curve, operating_point, max_background_fpr) {
  feasible <- curve[curve$background_fpr <= as.numeric(max_background_fpr) + 1e-12, , drop = FALSE]
  rrisk11_assert(nrow(feasible) > 0L, paste("No threshold satisfies FPR cap for", operating_point, "including no-trigger sentinel."))
  ordering <- order(-feasible$recall, -feasible$precision, -feasible$threshold)
  winner <- feasible[ordering[[1L]], , drop = FALSE]
  winner$operating_point <- operating_point
  winner$max_background_fpr <- as.numeric(max_background_fpr)
  winner$selection_mode <- if (isTRUE(winner$is_no_trigger[[1L]])) "no_trigger" else "constrained_max_recall"
  winner
}

rrisk11_select_operating_points <- function(inner_oof, context) {
  curve <- rrisk11_threshold_curve(
    inner_oof$observed_sr, inner_oof$calibrated_probability, inner_oof$regional_branch_id,
    inner_oof$branch_sqrt_weight, context
  )
  operating <- context$config$threshold$operating_points
  selected <- do.call(rbind, lapply(names(operating), function(name) {
    rrisk11_select_threshold(curve, name, operating[[name]]$max_background_fpr)
  }))
  rownames(selected) <- NULL
  list(selected = selected, curve = curve)
}

rrisk11_check_threshold_contract <- function(context) {
  observed <- c(0.76, 0.77, 0.71, 0.70, 0.74, 0.73)
  probability <- c(0.8, 0.8, 0.6, 0.4, 0.5, 0.3)
  branches <- paste0("b", seq_along(observed)); weight <- rep(1, length(observed))
  curve <- rrisk11_threshold_curve(observed, probability, branches, weight, context)
  rrisk11_assert(any(curve$threshold == 0.8 & curve$n_triggered == 2L), "Equal probabilities were split by the threshold curve.")
  selected <- rrisk11_select_threshold(curve, "synthetic", 0)
  rrisk11_assert(selected$recall[[1L]] == 1 && selected$background_fpr[[1L]] == 0, "Threshold constrained-max-Recall contract failed.")

  no_trigger_curve <- rrisk11_threshold_curve(
    c(0.71, 0.76, 0.77), c(0.9, 0.8, 0.7), c("bg", "p1", "p2"), c(1, 1, 1), context
  )
  no_trigger <- rrisk11_select_threshold(no_trigger_curve, "synthetic_zero_fpr", 0)
  rrisk11_assert(isTRUE(no_trigger$is_no_trigger[[1L]]) && no_trigger$selection_mode[[1L]] == "no_trigger", "No-trigger fallback contract failed.")
  invisible(TRUE)
}
