file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run with Rscript training/regional_expert/regional_risk_v2/scripts/run.R", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE); project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_root <- normalizePath(file.path(project_dir, "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE); river_sr_activate(repo_root)
for (file in c("io.R", "validation.R", "preprocessing.R", "probability_rf.R", "shallow_boosting.R", "threshold.R", "metrics.R", "decision.R")) source(file.path(project_dir, "R", file), local = globalenv())
for (file in sprintf("%02d_%s.R", 1:6, c("validate_input", "prepare_folds", "check", "run_task", "aggregate", "summarize"))) source(file.path(project_dir, "scripts", file), local = globalenv())
context <- rrisk2_context(repo_root, project_dir); cli <- rrisk2_parse_cli(commandArgs(trailingOnly = TRUE))
if (identical(cli$stage, "prepare")) { validated <- stage_rrisk2_validate_input(context); stage_rrisk2_prepare_folds(context, validated, force = cli$force); quit(save = "no", status = 0L) }
if (identical(cli$stage, "check")) { stage_rrisk2_check(context); quit(save = "no", status = 0L) }
if (!is.null(cli$task_id)) { rrisk2_assert(is.null(cli$stage), "--task-id cannot be combined with --stage."); stage_rrisk2_run_task(context, cli$task_id, force = cli$force); quit(save = "no", status = 0L) }
if (identical(cli$stage, "aggregate")) { rrisk2_assert(!is.null(cli$run_id), "Aggregation requires --run-id."); tryCatch(stage_rrisk2_aggregate(context, cli$run_id), error = function(e) { if (dir.exists(rrisk2_run_dir(context, cli$run_id))) rrisk2_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(e))); stop(e) }); quit(save = "no", status = 0L) }
if (identical(cli$stage, "summarize")) { rrisk2_assert(!is.null(cli$run_id), "Summarization requires --run-id."); tryCatch(stage_rrisk2_summarize(context, cli$run_id), error = function(e) { if (dir.exists(rrisk2_run_dir(context, cli$run_id))) rrisk2_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(e))); stop(e) }); quit(save = "no", status = 0L) }
rrisk2_assert(FALSE, "Specify --stage prepare|check|aggregate|summarize or --task-id 1..68. There is no implicit full-training mode.")
