options(stringsAsFactors = FALSE)
suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
})

site_dir <- Sys.getenv("SR_GLOBAL_DIR", unset = "/home/zhangmeng/projects/sr_global")
site_dir <- normalizePath(site_dir, winslash = "/", mustWork = FALSE)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

dir_create <- function(...) {
  p <- file.path(...)
  dir.create(p, recursive = TRUE, showWarnings = FALSE)
  p
}

find_first_existing <- function(paths, label = "file") {
  hit <- paths[file.exists(paths)]
  if (length(hit) == 0) stop("Cannot find ", label, ". Checked:\n", paste(paths, collapse = "\n"))
  normalizePath(hit[[1]], winslash = "/", mustWork = TRUE)
}

pick_col <- function(x, candidates, required = TRUE, label = NULL) {
  nm <- names(x)
  idx <- match(tolower(candidates), tolower(nm))
  idx <- idx[!is.na(idx)]
  if (length(idx) > 0) return(nm[idx[[1]]])
  if (required) stop("Cannot identify ", label %||% paste(candidates, collapse = "/"),
                     ". Available columns:\n", paste(nm, collapse = ", "))
  NA_character_
}

safe_numeric <- function(x) suppressWarnings(as.numeric(x))

region_codes <- c("af", "ar", "as", "au", "eu", "gr", "na", "sa", "si")

hydrorivers_path <- function(region) {
  file.path(site_dir, "data_raw", "hydrosheds", "HydroRIVERS_global",
            paste0("HydroRIVERS_v10_", region, "_shp"),
            paste0("HydroRIVERS_v10_", region, ".shp"))
}

message("site_dir: ", site_dir)
