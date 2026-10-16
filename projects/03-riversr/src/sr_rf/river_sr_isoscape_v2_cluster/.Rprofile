local({
  conda_prefix <- Sys.getenv("CONDA_PREFIX", unset = "")
  if (nzchar(conda_prefix)) {
    conda_library <- file.path(conda_prefix, "lib")
    repo_root <- normalizePath("..", mustWork = FALSE)
    wrapper_bin <- file.path(repo_root, "environment", "bin")
    prepend_path <- function(value, current = "") {
      entries <- c(value, current)
      paste(entries[nzchar(entries)], collapse = .Platform$path.sep)
    }

    Sys.setenv(
      RENV_PATHS_LIBRARY = file.path(conda_prefix, "renv-library", "sr_rf"),
      RENV_PATHS_LIBRARY_STAGING = file.path(conda_prefix, "renv-staging", "sr_rf"),
      RENV_CONFIG_AUTO_SNAPSHOT = "FALSE",
      RENV_CONFIG_VCS_MANAGE_IGNORES = "FALSE",
      PATH = prepend_path(wrapper_bin, Sys.getenv("PATH", unset = "")),
      GDAL_DATA = file.path(conda_prefix, "share", "gdal"),
      PROJ_DATA = file.path(conda_prefix, "share", "proj"),
      PROJ_LIB = file.path(conda_prefix, "share", "proj"),
      DYLD_FALLBACK_LIBRARY_PATH = prepend_path(
        conda_library,
        Sys.getenv("DYLD_FALLBACK_LIBRARY_PATH", unset = "")
      ),
      LD_LIBRARY_PATH = prepend_path(
        conda_library,
        Sys.getenv("LD_LIBRARY_PATH", unset = "")
      )
    )
  }

  source("renv/activate.R")

  generated_ignore <- file.path("renv", ".gitignore")
  if (file.exists(generated_ignore)) {
    unlink(generated_ignore)
  }
})
