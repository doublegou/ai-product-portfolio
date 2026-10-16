stage_rrisk_check_folds <- function(context) {
  frozen <- rrisk_assert_folds_current(context)
  stage_rrisk_check_task_manifest(context)
  dat <- frozen$validated$data
  branch_map <- frozen$branches[match(dat[[context$config$columns$row_id]], frozen$branches$row_id), , drop = FALSE]
  dat$.regional_branch_id <- branch_map$regional_branch_id
  for (fold in seq_len(as.integer(context$config$validation$expected_outer_folds))) {
    heldout <- unique(branch_map$regional_branch_id[branch_map$branch_order == fold])
    analysis <- dat[dat$.regional_branch_id != heldout, , drop = FALSE]
    inner <- rrisk_build_inner_folds(analysis, heldout, context)
    rrisk_assert(inner$k %in% c(5L, 3L), "Elastic Inner engineering check returned an unsupported fold count.")
    joined <- analysis[match(inner$assignments$row_id, analysis[[context$config$columns$row_id]]), , drop = FALSE]
    for (inner_fold in seq_len(inner$k)) {
      y <- joined$.label[inner$assignments$inner_fold == inner_fold]
      rrisk_assert(setequal(unique(y), 0:1), paste("Elastic Inner assessment lacks a class: Outer", fold, "Inner", inner_fold))
    }
    crossing <- stats::aggregate(inner_fold ~ regional_branch_id, inner$assignments, function(x) length(unique(x)))
    rrisk_assert(all(crossing$inner_fold == 1L), "A regional branch crosses an Elastic Inner fold.")
  }
  rrisk_assert(inherits(rrisk_gam_formula("spatial_only", context), "formula"), "Spatial GAM formula is invalid.")
  rrisk_assert(inherits(rrisk_gam_formula("environment", context), "formula"), "Environment GAM formula is invalid.")
  rrisk_assert(inherits(rrisk_gam_formula("combined", context), "formula"), "Combined GAM formula is invalid.")
  rrisk_check_gam_interface(context)
  rrisk_assert(all(frozen$tasks$task_id[1:51] %in% 1:51) && all(frozen$tasks$model_type[1:51] == "gam"), "GAM Slurm task range changed.")
  rrisk_assert(all(frozen$tasks$task_id[52:85] %in% 52:85) && all(frozen$tasks$model_type[52:85] == "elastic_net"), "Elastic Slurm task range changed.")
  rrisk_log(
    "Engineering check passed: ", nrow(frozen$validated$data), " rows, ",
    length(unique(frozen$branches$regional_branch_id)), " exhaustive branches, ", nrow(frozen$tasks),
    " tasks, 17 grouped Inner designs, and one synthetic GAM interface contract; no formal task fitted."
  )
  invisible(frozen)
}
