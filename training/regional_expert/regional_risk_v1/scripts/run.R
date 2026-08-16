file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run with Rscript training/regional_expert/regional_risk_v1/scripts/run.R", call. = FALSE)

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_root <- normalizePath(file.path(project_dir, "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)

for (file in c("io.R", "validation.R", "branches.R", "folds.R", "preprocessing.R", "metrics.R", "gam.R", "elastic_net.R", "decision.R")) {
  source(file.path(project_dir, "R", file), local = globalenv())
}
for (file in sprintf("%02d_%s.R", 1:7, c("validate_input", "build_branches", "build_lobo_tasks", "check_folds", "run_task", "aggregate_oof", "summarize_run"))) {
  source(file.path(project_dir, "scripts", file), local = globalenv())
}

context <- rrisk_context(repo_root, project_dir)
cli <- rrisk_parse_cli(commandArgs(trailingOnly = TRUE))

if (identical(cli$stage, "prepare")) {
  validated <- stage_rrisk_validate_input(context); stage_rrisk_build_folds(context, validated, force = cli$force)
  quit(save = "no", status = 0L)
}
if (identical(cli$stage, "check")) { stage_rrisk_check_folds(context); quit(save = "no", status = 0L) }
if (!is.null(cli$task_id)) {
  rrisk_assert(is.null(cli$stage), "--task-id cannot be combined with --stage.")
  stage_rrisk_run_task(context, cli$task_id, force = cli$force); quit(save = "no", status = 0L)
}
if (identical(cli$stage, "aggregate")) {
  rrisk_assert(!is.null(cli$run_id), "Aggregation requires --run-id.")
  tryCatch(stage_rrisk_aggregate_oof(context, cli$run_id), error = function(error) { if (dir.exists(rrisk_run_dir(context, cli$run_id))) rrisk_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(error))); stop(error) })
  quit(save = "no", status = 0L)
}
if (identical(cli$stage, "summarize")) {
  rrisk_assert(!is.null(cli$run_id), "Summarization requires --run-id.")
  tryCatch(stage_rrisk_summarize_run(context, cli$run_id), error = function(error) { if (dir.exists(rrisk_run_dir(context, cli$run_id))) rrisk_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(error))); stop(error) })
  quit(save = "no", status = 0L)
}
rrisk_assert(FALSE, "Specify --stage prepare|check|aggregate|summarize or --task-id 1..85. There is no implicit full-training mode.")
