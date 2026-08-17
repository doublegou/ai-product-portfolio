#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
raw <- commandArgs(trailingOnly = TRUE)
command <- if (length(raw)) raw[[1L]] else ""
rest <- if (length(raw) > 1L) raw[-1L] else character()
args <- v3_parse_args(rest)
rscript <- file.path(R.home("bin"), "Rscript")

run_script <- function(name, arguments = character()) {
  path <- file.path(context$base, "scripts", name)
  status <- system2(rscript, c(path, arguments))
  if (!identical(status, 0L)) stop("Stage failed: ", name, call. = FALSE)
}

if (command == "prepare") {
  run_script("01_prepare.R")
} else if (command == "primary") {
  run_script("02_primary_task.R", rest)
} else if (command == "aggregate-primary") {
  run_script("03_aggregate_primary.R", rest)
} else if (command == "deployment") {
  run_script("04_select_deployment.R", rest)
} else if (command == "stress") {
  run_script("05_stress_task.R", rest)
} else if (command == "finalize") {
  run_script("06_finalize.R", rest)
} else if (command == "check") {
  run_script("07_check.R", rest)
} else if (command == "test") {
  run_script(file.path("..", "tests", "test_contracts.R"))
} else if (command == "smoke") {
  run_id <- as.character(args$`run-id` %||% paste0("smoke_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  if (!file.exists(file.path(context$base, "folds", "manifest.json"))) run_script("01_prepare.R")
  v3_write_run_manifest(context, run_id, list(mode = "smoke"))
  for (model in c("rf", "xgb")) {
    run_script("02_primary_task.R", c("--model", model, "--task", "1", "--run-id", run_id, "--smoke"))
  }
  message("Smoke test complete: ", run_id)
} else {
  stop(paste(
    "Usage:",
    "  Rscript training/base/v3/scripts/run.R prepare",
    "  Rscript training/base/v3/scripts/run.R test",
    "  Rscript training/base/v3/scripts/run.R smoke --run-id <id>",
    "  Rscript training/base/v3/scripts/run.R primary --model rf|xgb --task 1..15 --run-id <id>",
    "  Rscript training/base/v3/scripts/run.R aggregate-primary --run-id <id>",
    "  Rscript training/base/v3/scripts/run.R deployment --model rf|xgb --run-id <id>",
    "  Rscript training/base/v3/scripts/run.R stress --model rf|xgb --task 1..20 --run-id <id>",
    "  Rscript training/base/v3/scripts/run.R finalize --run-id <id>",
    "  Rscript training/base/v3/scripts/run.R check --run-id <id>",
    sep = "\n"
  ), call. = FALSE)
}
