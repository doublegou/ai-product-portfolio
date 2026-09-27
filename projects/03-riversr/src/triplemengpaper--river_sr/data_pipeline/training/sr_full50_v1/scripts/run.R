file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this file with Rscript.", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
scripts_dir <- dirname(script_path)
source(file.path(scripts_dir, "common.R"), local = TRUE)
context <- river_sr_context(script_path)
rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)
steps <- list(
  list(script = "01_build_candidate_sites.R", outputs = c("candidate_sites")),
  list(script = "08_assemble_full50.R", outputs = c("full50", "processed")),
  list(script = "09_validate_release.R", outputs = c("manifest"))
)

step_output_paths <- function(step) {
  vapply(
    step$outputs,
    function(name) river_sr_path(context, context$config$output[[name]]),
    character(1L),
    USE.NAMES = FALSE
  )
}

args <- commandArgs(trailingOnly = TRUE)
unknown_args <- setdiff(args, c("--resume"))
river_sr_assert(
  length(unknown_args) == 0L,
  paste("Unknown argument(s):", paste(unknown_args, collapse = ", "), "Supported: --resume")
)

steps_to_run <- seq_along(steps)
if ("--resume" %in% args) {
  completed <- vapply(
    steps,
    function(step) all(file.exists(step_output_paths(step))),
    logical(1L)
  )
  if (all(completed)) {
    message("All pipeline checkpoints already exist; nothing to resume.")
    quit(save = "no", status = 0L)
  }
  first_incomplete <- which(!completed)[[1L]]
  steps_to_run <- seq.int(first_incomplete, length(steps))
  message(sprintf(
    "Resume mode: %d completed step(s); restarting at %s",
    first_incomplete - 1L,
    steps[[first_incomplete]]$script
  ))
}

for (step_index in steps_to_run) {
  step <- steps[[step_index]]
  message("Running ", step$script)
  status <- system2(
    rscript,
    args = shQuote(normalizePath(file.path(scripts_dir, step$script), mustWork = TRUE))
  )
  if (!identical(status, 0L)) {
    stop("Pipeline stopped at ", step$script, " (exit code ", status, ").", call. = FALSE)
  }
  missing_outputs <- step_output_paths(step)[!file.exists(step_output_paths(step))]
  river_sr_assert(
    length(missing_outputs) == 0L,
    paste("Step finished without writing checkpoint output(s):", paste(missing_outputs, collapse = ", "))
  )
}

message("Training sr_full50_v1 pipeline completed successfully.")
