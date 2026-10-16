file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run with Rscript data_pipeline/training/regional_expert/risk_v2/scripts/run.R", call. = FALSE)

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_root <- normalizePath(file.path(project_dir, "..", "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)
source(file.path(project_dir, "scripts", "common.R"), local = globalenv())
regional_v2_require(c("yaml", "jsonlite", "digest", "data.table"))

context <- list(
  repo_root = repo_root,
  project_dir = project_dir,
  config = yaml::read_yaml(file.path(project_dir, "config", "default.yml"))
)
for (file in c("01_validate_inputs.R", "02_add_process14.R", "03_validate_output.R")) {
  source(file.path(project_dir, "scripts", file), local = globalenv())
}

regional_v2_log("Validating frozen V1 regional table, branch map, and Process14 contract.")
validated <- regional_v2_validate_inputs(context)
dat <- regional_v2_add_process14(validated, context)
regional_v2_validate_output(dat, validated, context)
output <- regional_v2_path(context, context$config$output$table)
regional_v2_write_csv(dat, output)
published <- regional_v2_read_csv(output)
regional_v2_validate_published_output(published, validated, context)
manifest <- regional_v2_write_manifest(output, validated, context)
regional_v2_log(
  "Published ", nrow(dat), " x ", ncol(dat), " to ", output,
  "; Process14 status=", context$config$formula_contract$status,
  "; manifest=", manifest, "."
)
