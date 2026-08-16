file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run with Rscript data_pipeline/training/regional_expert/risk_v1/scripts/run.R", call. = FALSE)

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_root <- normalizePath(file.path(project_dir, "..", "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)
source(file.path(project_dir, "scripts", "common.R"), local = globalenv())
regional_data_require(c("yaml", "jsonlite", "digest", "data.table", "sf"))

context <- list(
  repo_root = repo_root,
  project_dir = project_dir,
  config = yaml::read_yaml(file.path(project_dir, "config", "default.yml"))
)
for (file in c("01_validate_inputs.R", "02_build_himalaya_domain.R", "03_add_regional_fields.R", "04_validate_output.R")) {
  source(file.path(project_dir, "scripts", file), local = globalenv())
}

regional_data_log("Validating Full50 and frozen Base V2 topology.")
validated <- regional_data_validate_inputs(context)
dat <- regional_data_build_domain(validated, context)
dat <- regional_data_add_fields(dat, context)
regional_data_validate_output(dat, context)
output <- regional_data_path(context, context$config$output$table)
regional_data_write_csv(dat, output)
regional_data_log("Published ", nrow(dat), " rows to ", output, "; positives=", sum(dat$high_sr_label), ".")
