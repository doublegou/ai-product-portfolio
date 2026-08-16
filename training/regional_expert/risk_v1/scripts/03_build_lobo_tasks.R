# Task expansion is intentionally kept as a named stage file for auditability.
# The immutable 17 x 5 task manifest is created by stage_rrisk_build_folds().
stage_rrisk_check_task_manifest <- function(context) {
  tasks <- rrisk_read_csv(rrisk_fold_paths(context)[["tasks"]])
  rrisk_assert(nrow(tasks) == 85L && setequal(tasks$task_id, 1:85), "Regional Risk V1 task manifest is not the frozen 85-task design.")
  invisible(tasks)
}
