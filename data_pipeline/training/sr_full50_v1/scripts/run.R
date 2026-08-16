file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this file with Rscript.", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
scripts_dir <- dirname(script_path)
source(file.path(scripts_dir, "common.R"), local = TRUE)
context <- river_sr_context(script_path)
inventory_path <- river_sr_path(context, "data/raw/features/download_inventory.csv")
source_config_path <- river_sr_path(context, "data_pipeline/raw_features/config/sources.yml")
river_sr_assert(file.exists(inventory_path), paste(
  "Raw features are not prepared. Run: Rscript data_pipeline/raw_features/run.R"
))
river_sr_assert(file.exists(source_config_path), paste("Missing raw source manifest:", source_config_path))
inventory <- data.table::fread(inventory_path)
source_config <- yaml::read_yaml(source_config_path)
expected_ids <- vapply(source_config$sources, `[[`, character(1L), "id")
verified_ids <- inventory[status == "verified", id]
river_sr_assert(setequal(expected_ids, verified_ids), paste(
  "Raw feature inventory is incomplete. Run: Rscript data_pipeline/raw_features/run.R"
))
rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)
steps <- list(
  list(script = "01_build_candidate_sites.R", outputs = c("candidate_sites")),
  list(script = "02_assign_hydrobasins.R", outputs = c("basin_assignment", "basin_scope")),
  list(script = "03_extract_hydrology.R", outputs = c("hydrology")),
  list(script = "04_extract_geology.R", outputs = c("geology")),
  list(script = "05_extract_climate_terrain.R", outputs = c("climate_terrain")),
  list(script = "06_extract_soil.R", outputs = c("soil")),
  list(script = "07_extract_geologic_age.R", outputs = c("geologic_age")),
  list(script = "08_assemble_full50.R", outputs = c("full50", "processed"))
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
