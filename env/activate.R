river_sr_find_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)

  repeat {
    if (file.exists(file.path(current, "env", "renv.lock"))) {
      return(current)
    }

    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Cannot find the RiverSR repository root.", call. = FALSE)
    }
    current <- parent
  }
}

river_sr_library_path <- function(repo_root) {
  os_name <- if (.Platform$OS.type == "windows") "windows" else Sys.info()[["sysname"]]
  file.path(
    repo_root,
    "env",
    "library",
    tolower(os_name),
    paste0("R-", paste(R.version$major, strsplit(R.version$minor, "\\.")[[1L]][1L], sep = ".")),
    R.version$platform
  )
}

river_sr_activate <- function(repo_root = river_sr_find_root()) {
  if (getRversion() < "4.3.0") {
    stop("RiverSR requires R >= 4.3.0; found ", getRversion(), call. = FALSE)
  }

  project_library <- river_sr_library_path(repo_root)
  if (!dir.exists(project_library)) {
    stop("RiverSR environment is missing. Run: Rscript env/bootstrap.R", call. = FALSE)
  }

  .libPaths(c(project_library, .libPaths()))
  options(repos = c(CRAN = Sys.getenv("RIVER_SR_CRAN", "https://cloud.r-project.org")))
  invisible(project_library)
}
