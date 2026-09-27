stage_rrisk2_check <- function(context) {
  frozen <- rrisk2_assert_folds_current(context)
  for (fold in 1:17) {
    x <- frozen$outer[frozen$outer$outer_fold == fold, , drop = FALSE]; heldout <- unique(x$heldout_branch)
    rrisk2_assert(nrow(x) == 372L && length(heldout) == 1L && all(x$regional_branch_id[x$role == "assessment"] == heldout), paste("Outer fold invalid:", fold))
    analysis <- unique(x$regional_branch_id[x$role == "analysis"])
    rrisk2_assert(length(analysis) == 16L && !heldout %in% analysis, paste("Outer leakage:", fold))
    for (inner in analysis) rrisk2_assert(length(setdiff(analysis, inner)) == 15L && !heldout %in% c(inner, setdiff(analysis, inner)), paste("Inner leakage:", fold))
  }
  rrisk2_check_threshold_contract(context)
  set.seed(17); x <- matrix(rnorm(240), nrow = 40, dimnames = list(NULL, paste0("x", 1:6))); y <- rep(0:1, each = 20); w <- rep(1, 40)
  rf <- rrisk2_fit_model("probability_rf", x, y, w, 17L, context); boost <- rrisk2_fit_model("shallow_boosting", x, y, w, 18L, context)
  rrisk2_assert(length(rrisk2_predict_model(rf, x[1:5, , drop = FALSE])) == 5L && length(rrisk2_predict_model(boost, x[1:5, , drop = FALSE])) == 5L, "Model interface check failed.")
  rrisk2_assert(nrow(rrisk2_importance_model(rf, colnames(x))) == 6L && nrow(rrisk2_importance_model(boost, colnames(x))) == 6L, "Importance interface check failed.")
  rrisk2_log("Engineering check passed: frozen inputs, 17x nested LOBO, 68 tasks, threshold contract and both synthetic model interfaces; no Himalayan model fitted.")
  invisible(frozen)
}
