project_dir <- normalizePath(getwd(), mustWork = TRUE)
conda_prefix <- Sys.getenv("CONDA_PREFIX", unset = "")

if (!nzchar(conda_prefix) || basename(conda_prefix) != "sr_rf") {
  stop("Activate the Conda environment 'sr_rf' before restoring R packages.")
}

Sys.setenv(
  RENV_PATHS_LIBRARY = file.path(conda_prefix, "renv-library", "sr_rf"),
  RENV_CONFIG_AUTO_SNAPSHOT = "FALSE",
  RENV_CONFIG_VCS_MANAGE_IGNORES = "FALSE"
)

renv::restore(project = project_dir, prompt = FALSE)

generated_ignore <- file.path(project_dir, "renv", ".gitignore")
if (file.exists(generated_ignore)) {
  unlink(generated_ignore)
}
