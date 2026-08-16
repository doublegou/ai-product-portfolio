file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
scripts_dir <- dirname(script_path)
project_dir <- dirname(scripts_dir)
repo_root <- project_dir
repeat {
  if (file.exists(file.path(repo_root, "env", "activate.R"))) break
  parent <- dirname(repo_root)
  if (identical(parent, repo_root)) stop("Cannot find the RiverSR repository root.", call. = FALSE)
  repo_root <- parent
}
repo_root <- normalizePath(repo_root, mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)

for (file in c("io.R", "validation.R", "topology.R", "folds.R", "imputation.R", "metrics.R", "rf.R")) {
  source(file.path(project_dir, "R", file), local = FALSE)
}
for (file in c(
  "01_validate_input.R", "02_prepare_topology.R", "03_check_folds.R",
  "04_run_primary.R", "05_deployment_tuning.R", "06_run_stress.R",
  "07_fit_final_model.R", "08_summarize_run.R"
)) source(file.path(scripts_dir, file), local = FALSE)

context <- v2_context(repo_root, project_dir)
cli <- v2_parse_cli(commandArgs(trailingOnly = TRUE))
stage <- cli$stage
v2_assert(!is.null(stage) || !is.null(cli$task_type), paste(
  "No stage supplied. Use --stage prepare/check/primary/deployment/stress/finalize/release.",
  "There is deliberately no implicit full-training mode."
))

if (identical(stage, "prepare")) {
  stage_prepare_v2(context, force = cli$force)
} else if (identical(stage, "check")) {
  stage_check_v2(context)
} else if (identical(stage, "primary") || identical(cli$task_type, "primary")) {
  v2_assert(!is.null(cli$repeat_id) && !is.null(cli$outer_fold), "Primary requires --repeat-id and --outer-fold.")
  stage_run_primary_task(context, cli$repeat_id, cli$outer_fold, force = cli$force)
} else if (identical(stage, "deployment")) {
  v2_assert(!is.null(cli$run_id), "Deployment requires --run-id.")
  v2_begin_run(context, cli$run_id, commandArgs(trailingOnly = TRUE))
  stage_deployment_tuning(context, cli$run_id, force = cli$force)
} else if (identical(stage, "stress") || identical(cli$task_type, "stress")) {
  v2_assert(!is.null(cli$run_id) && !is.null(cli$scheme) && !is.null(cli$outer_fold), "Stress requires --run-id, --scheme and --outer-fold.")
  v2_begin_run(context, cli$run_id, commandArgs(trailingOnly = TRUE))
  stage_run_stress_task(context, cli$run_id, cli$scheme, cli$outer_fold, force = cli$force)
} else if (identical(stage, "finalize")) {
  v2_assert(!is.null(cli$run_id), "Finalize requires --run-id.")
  v2_begin_run(context, cli$run_id, commandArgs(trailingOnly = TRUE))
  stage_summarize_run(context, cli$run_id)
  stage_fit_final_model(context, cli$run_id)
  v2_finish_run(context, cli$run_id, "complete", list(
    finalize_arguments = commandArgs(trailingOnly = TRUE),
    finalize_runtime = v2_runtime_info()
  ))
} else if (identical(stage, "release")) {
  v2_assert(!is.null(cli$run_id), "Release requires --run-id.")
  stage_release_run(context, cli$run_id, force = cli$force)
} else {
  stop(paste("Unknown Base V2 stage:", stage), call. = FALSE)
}
