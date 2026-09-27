rrisk2_threshold_curve <- function(observed, probability, branch_id, weight, context) {
  observed <- as.numeric(observed); probability <- as.numeric(probability); branch_id <- as.character(branch_id); weight <- as.numeric(weight)
  rrisk2_assert(length(unique(c(length(observed), length(probability), length(branch_id), length(weight)))) == 1L, "Threshold inputs differ in length.")
  rrisk2_assert(all(is.finite(c(observed, probability, weight))) && all(weight > 0), "Threshold inputs are invalid.")
  positive <- observed >= as.numeric(context$config$domain$positive_lower); background <- observed < as.numeric(context$config$domain$background_upper)
  gray <- !positive & !background; extreme <- observed >= as.numeric(context$config$domain$extreme_lower)
  rrisk2_assert(any(positive) && any(background), "Threshold selection requires positives and background.")
  ord <- order(-probability, seq_along(probability)); p <- probability[ord]; w <- weight[ord]
  positive <- positive[ord]; background <- background[ord]; gray <- gray[ord]; extreme <- extreme[ord]; branch_id <- branch_id[ord]
  ends <- which(!duplicated(p, fromLast = TRUE)); total <- cumsum(w); pos <- cumsum(w * positive); bg <- cumsum(w * background); gy <- cumsum(w * gray); ex <- cumsum(w * extreme)
  detected <- function(end, mask) length(unique(branch_id[seq_len(end)][mask[seq_len(end)]]))
  no_trigger <- max(1 + .Machine$double.eps, max(p) + .Machine$double.eps)
  data.frame(threshold = c(no_trigger, p[ends]), n_triggered = c(0L, ends),
    recall = c(0, pos[ends] / sum(w * positive)), precision = c(0, pos[ends] / total[ends]), background_fpr = c(0, bg[ends] / sum(w * background)),
    gray_zone_trigger_rate = c(0, gy[ends] / sum(w * gray)), extreme_recall = c(0, ex[ends] / sum(w * extreme)),
    positive_branches_detected = c(0L, vapply(ends, detected, integer(1L), mask = positive)),
    extreme_branches_detected = c(0L, vapply(ends, detected, integer(1L), mask = extreme)), is_no_trigger = c(TRUE, rep(FALSE, length(ends))), stringsAsFactors = FALSE)
}

rrisk2_select_threshold <- function(inner_oof, context) {
  curve <- rrisk2_threshold_curve(inner_oof$observed_sr, inner_oof$probability, inner_oof$regional_branch_id, inner_oof$branch_sqrt_weight, context)
  cap <- as.numeric(context$config$threshold$max_background_fpr); feasible <- curve[curve$background_fpr <= cap + 1e-12, , drop = FALSE]
  rrisk2_assert(nrow(feasible) > 0L, "No threshold satisfies FPR cap, including no-trigger sentinel.")
  winner <- feasible[order(-feasible$recall, -feasible$precision, -feasible$threshold)[1L], , drop = FALSE]
  winner$max_background_fpr <- cap; winner$selection_mode <- if (winner$is_no_trigger) "no_trigger" else "constrained_max_recall"
  list(selected = winner, curve = curve)
}

rrisk2_check_threshold_contract <- function(context) {
  x <- data.frame(observed_sr = c(.76, .77, .71, .70, .74, .73), probability = c(.8, .8, .6, .4, .5, .3), regional_branch_id = paste0("b", 1:6), branch_sqrt_weight = 1)
  selected <- rrisk2_select_threshold(x, context)$selected
  rrisk2_assert(selected$recall == 1 && selected$background_fpr == 0, "Nested FPR10 threshold contract failed.")
  invisible(TRUE)
}
