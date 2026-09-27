risk_select_threshold <- function(observed, probability, hydrological_group, context) {
  curve <- risk_threshold_curve(observed, probability, hydrological_group, context)
  max_fpr <- as.numeric(context$config$selection$max_background_fpr)
  min_precision <- as.numeric(context$config$selection$min_precision)
  feasible <- curve$background_fpr <= max_fpr & curve$precision_defined & curve$precision >= min_precision
  if (any(feasible)) {
    candidates <- curve[feasible, , drop = FALSE]
    candidates <- candidates[order(-candidates$recall, -candidates$positive_group_coverage, -candidates$threshold), , drop = FALSE]
    winner <- candidates[1L, , drop = FALSE]
    winner$inner_gate_feasible <- TRUE
    winner$threshold_selection_mode <- "feasible"
    winner$fallback_reason <- ""
  } else {
    candidates <- curve[curve$background_fpr <= max_fpr, , drop = FALSE]
    risk_assert(nrow(candidates) > 0L, "No threshold satisfies background FPR <= 5%, including the no-trigger threshold.")
    candidates <- candidates[order(
      -candidates$precision, -candidates$recall, -candidates$positive_group_coverage, -candidates$threshold
    ), , drop = FALSE]
    winner <- candidates[1L, , drop = FALSE]
    winner$inner_gate_feasible <- FALSE
    winner$threshold_selection_mode <- "fallback"
    winner$fallback_reason <- "no_threshold_met_precision_and_background_fpr_constraints"
  }
  list(selected = winner, curve = curve)
}

risk_rank_candidates <- function(summary, model) {
  pr_auc_order <- ifelse(is.finite(summary$pr_auc), summary$pr_auc, -Inf)
  if (identical(model, "elastic_net")) {
    ordering <- order(
      -as.integer(summary$inner_gate_feasible), -summary$recall, -summary$positive_group_coverage,
      -pr_auc_order, -summary$precision, summary$alpha, -summary$lambda_ratio, summary$candidate_id
    )
  } else {
    ordering <- order(
      -as.integer(summary$inner_gate_feasible), -summary$recall, -summary$positive_group_coverage,
      -pr_auc_order, -summary$precision, summary$mtry, -summary$min_node_size,
      summary$sample_fraction, summary$replace, summary$candidate_id
    )
  }
  result <- summary[ordering, , drop = FALSE]
  rownames(result) <- NULL
  result$candidate_rank <- seq_len(nrow(result))
  result
}

risk_candidate_metrics <- function(candidate_id, model, observed, probability, groups, context, parameters) {
  threshold_result <- risk_select_threshold(observed, probability, groups, context)
  selected <- threshold_result$selected
  row <- data.frame(
    candidate_id = candidate_id, model = model,
    threshold = selected$threshold, inner_gate_feasible = selected$inner_gate_feasible,
    threshold_selection_mode = selected$threshold_selection_mode,
    fallback_reason = selected$fallback_reason,
    n_predicted_positive = selected$n_predicted_positive,
    recall = selected$recall, precision = selected$precision, precision_defined = selected$precision_defined,
    background_fpr = selected$background_fpr, gray_zone_trigger_rate = selected$gray_zone_trigger_rate,
    positive_groups_detected = selected$positive_groups_detected,
    positive_group_coverage = selected$positive_group_coverage,
    extreme_groups_detected = selected$extreme_groups_detected,
    extreme_group_coverage = selected$extreme_group_coverage,
    pr_auc = risk_pr_auc(observed >= as.numeric(context$config$target$positive_lower), probability),
    roc_auc = risk_roc_auc(observed >= as.numeric(context$config$target$positive_lower), probability),
    stringsAsFactors = FALSE
  )
  for (name in names(parameters)) row[[name]] <- parameters[[name]]
  row
}
