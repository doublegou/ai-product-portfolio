file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run with Rscript training/global_correction/global_high_sr_risk/scripts/run.R", call. = FALSE)

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_root <- normalizePath(file.path(project_dir, "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)

for (file in c(
  "io.R", "validation.R", "folds.R", "preprocessing.R", "metrics.R", "threshold.R",
  "elastic_net.R", "probability_rf.R", "decision.R"
)) source(file.path(project_dir, "R", file), local = globalenv())
for (file in sprintf("%02d_%s.R", 1:5, c(
  "validate_input", "build_folds", "run_task", "aggregate_oof", "decide_feasibility"
))) source(file.path(project_dir, "scripts", file), local = globalenv())

context <- risk_context(repo_root, project_dir)
cli <- risk_parse_cli(commandArgs(trailingOnly = TRUE))

if (!is.null(cli$stage) && identical(cli$stage, "prepare")) {
  validated <- stage_risk_validate_input(context)
  stage_risk_build_folds(context, validated, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && identical(cli$stage, "check")) {
  frozen <- risk_assert_folds_current(context)
  tasks <- data.table::fread(risk_fold_paths(context)[["tasks"]], data.table = FALSE)
  risk_assert(nrow(tasks) == 30L, "Engineering check expected 30 tasks.")
  risk_log(
    "Engineering check passed: ", nrow(frozen$validated$data), " rows, ",
    length(frozen$validated$predictors), " predictors, 15 Outer designs, 30 training tasks."
  )
  quit(save = "no", status = 0L)
}

if (!is.null(cli$task_id)) {
  risk_assert(is.null(cli$stage), "--task-id cannot be combined with --stage.")
  stage_risk_run_task(context, cli$task_id, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && identical(cli$stage, "aggregate")) {
  risk_assert(!is.null(cli$run_id), "Aggregation requires --run-id.")
  tryCatch(
    stage_risk_aggregate_oof(context, cli$run_id, force = cli$force),
    error = function(error) {
      if (dir.exists(risk_run_dir(context, cli$run_id))) risk_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(error)))
      stop(error)
    }
  )
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && identical(cli$stage, "decide")) {
  risk_assert(!is.null(cli$run_id), "Decision requires --run-id.")
  options(river_sr.risk_v1.log_file = risk_run_dir(context, cli$run_id, "logs", "run.log"))
  tryCatch(
    stage_risk_decide_feasibility(context, cli$run_id),
    error = function(error) {
      if (dir.exists(risk_run_dir(context, cli$run_id))) risk_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(error)))
      stop(error)
    }
  )
  quit(save = "no", status = 0L)
}

risk_assert(FALSE, "Specify exactly one of --stage prepare|check|aggregate|decide or --task-id 1..30. There is no implicit full-training mode.")
