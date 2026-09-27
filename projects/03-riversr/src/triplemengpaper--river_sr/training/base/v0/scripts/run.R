file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run with Rscript training/base/v0/scripts/run.R", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_root <- normalizePath(file.path(project_dir, "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)

r_files <- c(
  "io.R",
  "validation.R",
  "folds_spatial_r51a.R",
  "folds_reference_r51b.R",
  "imputation.R",
  "metrics.R",
  "tune_rf.R",
  "final_consensus_r56a.R"
)
for (file in r_files) source(file.path(project_dir, "R", file), local = globalenv())

stage_files <- sprintf("%02d_%s.R", 1:6, c(
  "validate_input", "build_folds", "run_nested_cv", "select_final_params",
  "fit_final_model", "summarize_run"
))
for (file in stage_files) source(file.path(project_dir, "scripts", file), local = globalenv())

context <- v0_context(repo_root, project_dir)
cli <- v0_parse_cli(commandArgs(trailingOnly = TRUE))

if (!is.null(cli$release)) {
  options(river_sr.v0.log_file = v0_run_dir(context, cli$release, "logs", "run.log"))
  stage_release_run(context, cli$release, force = cli$force)
  quit(save = "no", status = 0L)
}

if (!is.null(cli$stage)) {
  v0_assert(identical(cli$stage, "prepare"), "The only standalone preparation stage is --stage prepare.")
  validated <- stage_validate_input(context)
  stage_build_folds(context, validated = validated, force = cli$force)
  quit(save = "no", status = 0L)
}

v0_assert(cli$mode %in% c("smoke", "full"), "--mode must be smoke or full.")
v0_assert(
  xor(is.null(cli$scheme), is.null(cli$outer_fold)) == FALSE,
  "--scheme and --outer-fold must be supplied together."
)
v0_assert_folds_current(context)

if (!is.null(cli$scheme)) {
  v0_assert(identical(cli$mode, "full"), "Scoped task execution is only available in full mode.")
  options(
    river_sr.v0.log_file = file.path(v0_task_dir(context, cli$scheme, cli$outer_fold), "run.log")
  )
  stage_run_nested_cv_task(
    context, cli$scheme, cli$outer_fold, force = cli$force, mode = "full"
  )
  quit(save = "no", status = 0L)
}

run_id <- if (is.null(cli$run_id)) v0_make_run_id(cli$mode) else cli$run_id
run_info <- v0_begin_run(context, run_id, cli$mode, commandArgs(trailingOnly = TRUE))

tryCatch(
  {
    if (identical(cli$mode, "smoke")) {
      scheme <- context$config$smoke$scheme
      outer_fold <- as.integer(context$config$smoke$outer_fold)
      smoke_dir <- v0_run_dir(context, run_id, "smoke", scheme, sprintf("fold_%02d", outer_fold))
      stage_run_nested_cv_task(
        context,
        scheme,
        outer_fold,
        output_dir = smoke_dir,
        inner_trees = as.integer(context$config$smoke$inner_trees),
        outer_trees = as.integer(context$config$smoke$outer_trees),
        force = cli$force,
        mode = "smoke"
      )
      v0_finish_run(context, run_id, run_info, "complete", list(smoke_task = paste(scheme, outer_fold)))
      v0_log("Smoke run complete: ", run_id)
    } else {
      stage_run_all_validation(context, force = cli$force)
      selected <- stage_select_final_params(context, run_id)
      stage_fit_final_model(context, run_id, selected)
      stage_summarize_run(context, run_id)
      v0_finish_run(context, run_id, run_info, "complete", list(validation_tasks = 20L))
      v0_log("Full V0 run complete: ", run_id)
    }
  },
  error = function(error) {
    v0_finish_run(context, run_id, run_info, "failed", list(error = conditionMessage(error)))
    stop(error)
  }
)
