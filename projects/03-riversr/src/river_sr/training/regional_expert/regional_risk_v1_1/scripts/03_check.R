stage_rrisk11_check <- function(context) {
  frozen <- rrisk11_assert_folds_current(context)
  v1_config <- yaml::read_yaml(rrisk11_path(context, context$config$input$v1_config))
  rrisk11_assert(identical(v1_config$gam, context$config$gam), "V1.1 GAM specification differs from frozen Regional Risk V1.")
  rrisk11_assert(identical(rrisk11_environment_predictors(context), rrisk11_read_lines(rrisk11_path(context, v1_config$input$environment_predictors))), "V1.1 predictor order differs from V1.")

  for (fold in seq_len(17L)) {
    current <- frozen$outer[frozen$outer$outer_fold == fold, , drop = FALSE]
    rrisk11_assert(nrow(current) == 372L && sum(current$role == "assessment") > 0L && sum(current$role == "analysis") > 0L, paste("Outer assignment invalid:", fold))
    heldout <- unique(current$heldout_branch)
    rrisk11_assert(length(heldout) == 1L && all(current$regional_branch_id[current$role == "assessment"] == heldout), paste("Held-out branch mismatch:", fold))
    analysis_branches <- unique(current$regional_branch_id[current$role == "analysis"])
    rrisk11_assert(length(analysis_branches) == 16L && !heldout %in% analysis_branches, paste("Outer leakage in fold:", fold))
    for (inner_branch in analysis_branches) {
      inner_train <- setdiff(analysis_branches, inner_branch)
      rrisk11_assert(length(inner_train) == 15L && !heldout %in% c(inner_train, inner_branch), paste("Inner leakage in Outer fold:", fold))
    }
  }
  rrisk11_assert(all(frozen$tasks$model_type == "gam") && all(frozen$tasks$task_id %in% 1:34), "Task manifest contains unsupported arms or IDs.")
  rrisk11_assert(inherits(rrisk11_gam_formula("environment", context), "formula") && inherits(rrisk11_gam_formula("combined", context), "formula"), "Frozen GAM formula construction failed.")
  rrisk11_check_gam_interface(context)
  rrisk11_check_platt_interface(context)
  rrisk11_check_threshold_contract(context)
  synthetic_oof <- data.frame(
    model_id = "synthetic", outer_fold = rep(1:4, each = 2L), regional_branch_id = rep(paste0("b", 1:4), each = 2L),
    row_id = paste0("r", 1:8), site_id = paste0("s", 1:8),
    observed_sr = c(0.70, 0.71, 0.73, 0.74, 0.76, 0.77, 0.81, 0.82),
    high_sr_label = c(0L, 0L, 0L, 0L, 1L, 1L, 1L, 1L), branch_sqrt_weight = rep(1, 8L),
    raw_probability = c(0.05, 0.08, 0.20, 0.30, 0.62, 0.70, 0.86, 0.92),
    calibrated_probability = c(0.04, 0.07, 0.18, 0.28, 0.65, 0.74, 0.89, 0.95),
    trigger_primary = c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE),
    trigger_strict = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE), stringsAsFactors = FALSE
  )
  probability_contract <- rbind(
    rrisk11_probability_metrics(synthetic_oof, "raw_probability", context),
    rrisk11_probability_metrics(synthetic_oof, "calibrated_probability", context)
  )
  primary_contract <- rrisk11_apply_primary_targets(rrisk11_gate_metrics(synthetic_oof, "primary", context), context)
  strict_contract <- rrisk11_gate_metrics(synthetic_oof, "strict", context)
  branch_contract <- rrisk11_branch_metrics(synthetic_oof, "primary", context)
  decision_contract <- rrisk11_decision_markdown(
    cbind(data.frame(model_id = "synthetic", stringsAsFactors = FALSE), primary_contract),
    probability_contract, context, "synthetic_engineering_check"
  )
  rrisk11_assert(nrow(probability_contract) == 2L && nrow(branch_contract) == 4L && nrow(strict_contract) == 1L && length(decision_contract) > 10L, "Metrics or Decision engineering contract failed.")
  rrisk11_assert(34L * 17L == as.integer(context$config$validation$expected_gam_fits), "Expected GAM-fit contract changed.")
  rrisk11_log(
    "Engineering check passed: 372 rows, 17 Outer folds, 34 tasks, 16 exhaustive Inner branches per task, ",
    "two synthetic GAM interfaces, weighted Platt, threshold edge, metrics and Decision contracts; no formal Himalayan task fitted."
  )
  invisible(frozen)
}
