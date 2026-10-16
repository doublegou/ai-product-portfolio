file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run with Rscript training/base/v1/scripts/run.R", call. = FALSE)

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_root <- normalizePath(file.path(project_dir, "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)

for (file in c("io.R", "validation.R", "folds.R", "imputation.R", "metrics.R", "rf.R")) {
  source(file.path(project_dir, "R", file), local = globalenv())
}
stage_files <- sprintf("%02d_%s.R", 1:7, c(
  "validate_input", "build_folds", "run_primary", "deployment_tuning",
  "run_stress", "fit_final_model", "summarize_run"
))
for (file in stage_files) source(file.path(project_dir, "scripts", file), local = globalenv())

context <- v1_context(repo_root, project_dir)
cli <- v1_parse_cli(commandArgs(trailingOnly = TRUE))

if (!is.null(cli$release)) {
  options(river_sr.v1.log_file = v1_run_dir(context, cli$release, "logs", "run.log"))
  stage_release_run(context, cli$release, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && cli$stage == "prepare") {
  validated <- stage_validate_input(context)
  stage_build_folds(context, validated, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && cli$stage == "check") {
  validated <- stage_validate_input(context)
  manifest <- v1_assert_folds_current(context)
  v1_log(
    "Engineering check passed: ", validated$n_rows, " rows, ", validated$n_predictors,
    " predictors, ", manifest$n_hydrological_groups, " hydrological groups."
  )
  quit(save = "no", status = 0L)
}

if (identical(cli$task_type, "primary")) {
  v1_assert(!is.null(cli$repeat_id) && !is.null(cli$outer_fold), "Primary task requires --repeat-id and --outer-fold.")
  stage_run_primary_task(context, cli$repeat_id, cli$outer_fold, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && cli$stage == "deployment") {
  v1_assert(!is.null(cli$run_id), "Deployment stage requires --run-id.")
  options(river_sr.v1.log_file = v1_run_dir(context, cli$run_id, "logs", "run.log"))
  stage_run_deployment_tuning(context, cli$run_id, force = cli$force)
  quit(save = "no", status = 0L)
}

if (identical(cli$task_type, "stress")) {
  v1_assert(!is.null(cli$run_id) && !is.null(cli$scheme) && !is.null(cli$outer_fold), "Stress task requires --run-id, --scheme and --outer-fold.")
  stage_run_stress_task(context, cli$run_id, cli$scheme, cli$outer_fold, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage) && cli$stage == "finalize") {
  v1_assert(!is.null(cli$run_id), "Finalize stage requires --run-id.")
  options(river_sr.v1.log_file = v1_run_dir(context, cli$run_id, "logs", "run.log"))
  tryCatch(
    {
      stage_fit_final_model(context, cli$run_id)
      stage_summarize_run(context, cli$run_id)
      v1_finish_run(context, cli$run_id, "complete", list(primary_tasks = 15L, stress_tasks = 20L))
    },
    error = function(error) {
      v1_finish_run(context, cli$run_id, "failed", list(error = conditionMessage(error)))
      stop(error)
    }
  )
  quit(save = "no", status = 0L)
}

v1_assert(is.null(cli$task_type) && is.null(cli$stage), "Unknown or incomplete scoped execution arguments.")
run_id <- if (is.null(cli$run_id)) v1_make_run_id() else cli$run_id
v1_begin_run(context, run_id, commandArgs(trailingOnly = TRUE))
tryCatch(
  {
    v1_assert_folds_current(context)
    stage_run_all_primary(context, force = cli$force)
    stage_run_deployment_tuning(context, run_id, force = cli$force)
    stage_run_all_stress(context, run_id, force = cli$force)
    stage_fit_final_model(context, run_id)
    stage_summarize_run(context, run_id)
    v1_finish_run(context, run_id, "complete", list(primary_tasks = 15L, stress_tasks = 20L))
    v1_log("Full Base V1 run complete: ", run_id)
  },
  error = function(error) {
    v1_finish_run(context, run_id, "failed", list(error = conditionMessage(error)))
    stop(error)
  }
)
