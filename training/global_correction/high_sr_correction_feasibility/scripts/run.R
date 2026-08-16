file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run with Rscript training/global_correction/high_sr_correction_feasibility/scripts/run.R", call. = FALSE)

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_root <- normalizePath(file.path(project_dir, "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)

for (file in c("io.R", "preprocessing.R", "metrics.R", "validation.R", "base_rf.R", "elastic_net.R", "residual_rf.R", "decision.R")) {
  source(file.path(project_dir, "R", file), local = globalenv())
}
for (file in sprintf("%02d_%s.R", 1:6, c("validate_input", "build_tasks", "run_base_task", "run_correction_task", "aggregate_oof", "decide_feasibility"))) {
  source(file.path(project_dir, "scripts", file), local = globalenv())
}

context <- corr_context(repo_root, project_dir)
cli <- corr_parse_cli(commandArgs(trailingOnly = TRUE))

if (!is.null(cli$stage) && identical(cli$stage, "prepare")) {
  validated <- stage_corr_validate_input(context)
  stage_corr_build_tasks(context, validated, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && identical(cli$stage, "check")) {
  frozen <- corr_assert_frozen_current(context)
  corr_assert(nrow(frozen$base_tasks) == 15L && nrow(frozen$correction_tasks) == 30L, "Engineering check expected 45 formal tasks.")
  corr_assert(nrow(frozen$base_fit_plan) == 240L, "Engineering check expected 240 canonical Base fits.")
  corr_log("Engineering check passed: 4,485 rows, 355 groups, 671 Oracle rows, 15 Base tasks, 30 correction tasks, 240 canonical Base fits.")
  quit(save = "no", status = 0L)
}

if (!is.null(cli$base_task_id)) {
  corr_assert(is.null(cli$stage) && is.null(cli$correction_task_id), "Base task cannot be combined with another action.")
  stage_corr_run_base_task(context, cli$base_task_id, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$correction_task_id)) {
  corr_assert(is.null(cli$stage) && is.null(cli$base_task_id), "Correction task cannot be combined with another action.")
  stage_corr_run_correction_task(context, cli$correction_task_id, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && identical(cli$stage, "aggregate")) {
  corr_assert(!is.null(cli$run_id), "Aggregate requires --run-id.")
  tryCatch(stage_corr_aggregate_oof(context, cli$run_id, force = cli$force), error = function(error) {
    if (dir.exists(corr_run_dir(context, cli$run_id))) corr_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(error)))
    stop(error)
  })
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && identical(cli$stage, "decide")) {
  corr_assert(!is.null(cli$run_id), "Decide requires --run-id.")
  tryCatch(stage_corr_decide_feasibility(context, cli$run_id), error = function(error) {
    if (dir.exists(corr_run_dir(context, cli$run_id))) corr_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(error)))
    stop(error)
  })
  quit(save = "no", status = 0L)
}

corr_assert(FALSE, "Specify exactly one action: --stage prepare|check|aggregate|decide, --base-task-id, or --correction-task-id. There is no smoke or implicit full-training mode.")
