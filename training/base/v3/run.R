file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this entry with Rscript.", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- dirname(script_path)
pipeline_path <- file.path(project_dir, "R", "pipeline.R")
config_path <- file.path(project_dir, "config.yml")

source(pipeline_path, local = TRUE)
run_project(config_path)
