source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble",
    "stringr",
    "purrr"
  )
)

library(dplyr)
library(readr)
library(tibble)
library(stringr)
library(purrr)

out_dir <- file.path(
  project_root(),
  "outputs/legacy_asset_audit"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

roots <- c(
  legacy_project = file.path(
    Sys.getenv("HOME"),
    "projects/sr_global"
  ),

  current_project = project_root()
)

root_status <- tibble(
  root_name = names(roots),
  root_path = unname(roots),
  exists = dir.exists(roots)
)

write_csv(
  root_status,
  file.path(
    out_dir,
    "audit_roots.csv"
  )
)

if (!dir.exists(roots[["legacy_project"]])) {
  stop(
    "Legacy project not found: ",
    roots[["legacy_project"]]
  )
}

# ------------------------------------------------------------
# 1. Process keyword dictionary
# ------------------------------------------------------------

keywords <- tribble(
  ~process_group, ~pattern, ~priority,

  "bedrock_sr",
  paste0(
    "bedrock[_ -]?sr|sr[_ -]?bedrock|",
    "bataille|radiogenic|",
    "87sr|sr87|isoscape"
  ),
  "critical",

  "geological_age",
  paste0(
    "geological[_ -]?age|geology[_ -]?age|",
    "rock[_ -]?age|bedrock[_ -]?age"
  ),
  "critical",

  "lithology",
  paste0(
    "litholog|glim|carbonate|evaporite|",
    "metamorphic|plutonic|volcanic|",
    "siliciclastic"
  ),
  "high",

  "runoff",
  paste0(
    "runoff|water[_ -]?yield|",
    "discharge|hydro.*flow"
  ),
  "critical",

  "glacier",
  paste0(
    "glacier|glaciated|ice[_ -]?cover|",
    "snow[_ -]?cover|permafrost"
  ),
  "critical",

  "terrain",
  paste0(
    "relief|rugged|slope|terrain|",
    "elevation|dem"
  ),
  "critical",

  "hydrogeology",
  paste0(
    "baseflow|base[_ -]?flow|",
    "permeab|porosity|aquifer|",
    "groundwater|recharge"
  ),
  "high",

  "upstream_aggregation",
  paste0(
    "upstream|upstream.*weight|",
    "area[_ -]?weight|runoff[_ -]?weight|",
    "flow[_ -]?accum|hydrobasin|",
    "hydroriver|river[_ -]?network"
  ),
  "critical",

  "soil_weathering",
  paste0(
    "soil|clay|weathering|regolith|",
    "soil[_ -]?depth"
  ),
  "medium",

  "aridity",
  paste0(
    "aridity|ai[_ -]?ratio|",
    "et0|evapotranspiration"
  ),
  "high",

  "concentration_flux",
  paste0(
    "concentration|solute|sr[_ -]?flux|",
    "flux[_ -]?weight"
  ),
  "locked"
)

# ------------------------------------------------------------
# 2. Full file inventory
# ------------------------------------------------------------

list_root_files <- function(
    root_name,
    root_path
) {
  if (!dir.exists(root_path)) {
    return(tibble())
  }

  paths <- list.files(
    root_path,
    recursive = TRUE,
    full.names = TRUE,
    include.dirs = FALSE,
    all.files = TRUE
  )

  if (length(paths) == 0L) {
    return(tibble())
  }

  info <- file.info(paths)

  root_norm <- normalizePath(
    root_path,
    mustWork = TRUE
  )

  path_norm <- normalizePath(
    paths,
    mustWork = FALSE
  )

  relative_path <- vapply(
    path_norm,
    function(x) {
      prefix <- paste0(
        root_norm,
        .Platform$file.sep
      )

      if (startsWith(x, prefix)) {
        substring(
          x,
          nchar(prefix) + 1L
        )
      } else {
        basename(x)
      }
    },
    character(1)
  )

  tibble(
    root_name = root_name,
    root_path = root_norm,
    path = path_norm,
    relative_path = relative_path,
    extension = tolower(
      tools::file_ext(path_norm)
    ),
    size_bytes = as.numeric(info$size),
    size_mb = as.numeric(info$size) /
      1024^2,
    modified_time = as.character(
      info$mtime
    )
  )
}

file_inventory <- imap_dfr(
  roots,
  ~ list_root_files(
    .y,
    .x
  )
)

write_csv(
  file_inventory,
  file.path(
    out_dir,
    "all_files.csv"
  )
)

cat(
  "Files inventoried: ",
  nrow(file_inventory),
  "\n"
)

# ------------------------------------------------------------
# 3. Keyword matches in filenames and paths
# ------------------------------------------------------------

path_keyword_hits <- map_dfr(
  seq_len(nrow(keywords)),
  function(i) {
    keyword_row <- keywords[i, ]

    file_inventory |>
      filter(
        str_detect(
          str_to_lower(relative_path),
          regex(
            keyword_row$pattern,
            ignore_case = TRUE
          )
        )
      ) |>
      mutate(
        process_group =
          keyword_row$process_group,

        keyword_priority =
          keyword_row$priority
      )
  }
)

write_csv(
  path_keyword_hits,
  file.path(
    out_dir,
    "path_keyword_hits.csv"
  )
)

# ------------------------------------------------------------
# 4. Search code and configuration files
# ------------------------------------------------------------

script_extensions <- c(
  "r",
  "rmd",
  "py",
  "sh",
  "slurm",
  "yaml",
  "yml",
  "txt",
  "md"
)

script_files <- file_inventory |>
  filter(
    extension %in%
      script_extensions,
    size_mb <= 5
  )

read_script_hits <- function(
    path,
    relative_path,
    root_name
) {
  content <- tryCatch(
    readLines(
      path,
      warn = FALSE,
      encoding = "UTF-8"
    ),
    error = function(e) {
      character()
    }
  )

  if (length(content) == 0L) {
    return(tibble())
  }

  map_dfr(
    seq_len(nrow(keywords)),
    function(i) {
      pattern_i <- keywords$pattern[i]

      hit_index <- which(
        str_detect(
          str_to_lower(content),
          regex(
            pattern_i,
            ignore_case = TRUE
          )
        )
      )

      if (length(hit_index) == 0L) {
        return(tibble())
      }

      tibble(
        root_name = root_name,
        path = path,
        relative_path = relative_path,
        process_group =
          keywords$process_group[i],
        keyword_priority =
          keywords$priority[i],
        line_number = hit_index,
        line_text = str_trim(
          content[hit_index]
        )
      )
    }
  )
}

script_keyword_hits <- pmap_dfr(
  script_files |>
    select(
      path,
      relative_path,
      root_name
    ),
  read_script_hits
)

write_csv(
  script_keyword_hits,
  file.path(
    out_dir,
    "script_keyword_hits.csv"
  )
)

# ------------------------------------------------------------
# 5. Audit RDS schemas
# ------------------------------------------------------------

rds_files <- file_inventory |>
  filter(
    extension == "rds",
    size_mb <= 1500
  )

audit_rds_file <- function(
    path,
    relative_path,
    root_name,
    size_mb
) {
  object <- tryCatch(
    readRDS(path),
    error = function(e) {
      structure(
        list(
          error_message =
            conditionMessage(e)
        ),
        class = "audit_read_error"
      )
    }
  )

  if (
    inherits(
      object,
      "audit_read_error"
    )
  ) {
    return(
      list(
        summary = tibble(
          root_name = root_name,
          path = path,
          relative_path = relative_path,
          size_mb = size_mb,
          object_class = "READ_ERROR",
          n_rows = NA_integer_,
          n_columns = NA_integer_,
          error_message =
            object$error_message
        ),

        columns = tibble()
      )
    )
  }

  object_class <- paste(
    class(object),
    collapse = ";"
  )

  if (
    is.data.frame(object) ||
    inherits(object, "tbl")
  ) {
    column_names <- names(object)

    column_hits <- map_dfr(
      seq_len(nrow(keywords)),
      function(i) {
        hit_columns <- column_names[
          str_detect(
            str_to_lower(column_names),
            regex(
              keywords$pattern[i],
              ignore_case = TRUE
            )
          )
        ]

        if (length(hit_columns) == 0L) {
          return(tibble())
        }

        tibble(
          root_name = root_name,
          path = path,
          relative_path = relative_path,
          size_mb = size_mb,
          n_rows = nrow(object),
          n_columns = ncol(object),
          process_group =
            keywords$process_group[i],
          keyword_priority =
            keywords$priority[i],
          column_name = hit_columns
        )
      }
    )

    result <- list(
      summary = tibble(
        root_name = root_name,
        path = path,
        relative_path = relative_path,
        size_mb = size_mb,
        object_class = object_class,
        n_rows = nrow(object),
        n_columns = ncol(object),
        error_message = NA_character_
      ),

      columns = column_hits
    )
  } else {
    result <- list(
      summary = tibble(
        root_name = root_name,
        path = path,
        relative_path = relative_path,
        size_mb = size_mb,
        object_class = object_class,
        n_rows = NA_integer_,
        n_columns = NA_integer_,
        error_message = NA_character_
      ),

      columns = tibble()
    )
  }

  rm(object)
  invisible(gc())

  result
}

rds_results <- pmap(
  rds_files |>
    select(
      path,
      relative_path,
      root_name,
      size_mb
    ),
  audit_rds_file
)

rds_object_summary <- map_dfr(
  rds_results,
  "summary"
)

rds_column_hits <- map_dfr(
  rds_results,
  "columns"
)

write_csv(
  rds_object_summary,
  file.path(
    out_dir,
    "rds_object_summary.csv"
  )
)

write_csv(
  rds_column_hits,
  file.path(
    out_dir,
    "rds_predictor_column_hits.csv"
  )
)

# ------------------------------------------------------------
# 6. Candidate raster/vector assets
# ------------------------------------------------------------

spatial_extensions <- c(
  "tif",
  "tiff",
  "vrt",
  "nc",
  "grd",
  "gpkg",
  "shp",
  "bil",
  "img"
)

spatial_assets <- path_keyword_hits |>
  filter(
    extension %in%
      spatial_extensions
  ) |>
  distinct(
    root_name,
    path,
    relative_path,
    extension,
    size_mb,
    process_group,
    keyword_priority
  ) |>
  arrange(
    factor(
      keyword_priority,
      levels = c(
        "critical",
        "high",
        "medium",
        "locked"
      )
    ),
    process_group,
    relative_path
  )

write_csv(
  spatial_assets,
  file.path(
    out_dir,
    "candidate_spatial_assets.csv"
  )
)

# ------------------------------------------------------------
# 7. Ranked shortlist
# ------------------------------------------------------------

path_score <- path_keyword_hits |>
  group_by(
    root_name,
    path,
    relative_path,
    extension,
    size_mb
  ) |>
  summarise(
    matched_processes = paste(
      sort(
        unique(process_group)
      ),
      collapse = "; "
    ),

    n_process_groups =
      n_distinct(process_group),

    n_critical = sum(
      keyword_priority ==
        "critical"
    ),

    n_high = sum(
      keyword_priority ==
        "high"
    ),

    .groups = "drop"
  ) |>
  mutate(
    extension_bonus = case_when(
      extension %in%
        c(
          "tif",
          "tiff",
          "vrt",
          "nc",
          "grd",
          "bil",
          "img"
        ) ~ 5,

      extension == "rds" ~ 4,

      extension %in%
        c(
          "gpkg",
          "shp",
          "csv",
          "parquet"
        ) ~ 3,

      extension %in%
        script_extensions ~ 2,

      TRUE ~ 0
    ),

    audit_score =
      5 * n_critical +
      3 * n_high +
      2 * n_process_groups +
      extension_bonus
  ) |>
  arrange(
    desc(audit_score),
    relative_path
  )

write_csv(
  path_score,
  file.path(
    out_dir,
    "priority_asset_shortlist.csv"
  )
)

# ------------------------------------------------------------
# 8. Process-level summary
# ------------------------------------------------------------

process_summary <- keywords |>
  select(
    process_group,
    priority
  ) |>
  left_join(
    path_keyword_hits |>
      count(
        process_group,
        name = "n_path_hits"
      ),
    by = "process_group"
  ) |>
  left_join(
    script_keyword_hits |>
      count(
        process_group,
        name = "n_script_hits"
      ),
    by = "process_group"
  ) |>
  left_join(
    rds_column_hits |>
      count(
        process_group,
        name = "n_rds_column_hits"
      ),
    by = "process_group"
  ) |>
  mutate(
    across(
      starts_with("n_"),
      ~ coalesce(
        .x,
        0L
      )
    )
  ) |>
  arrange(
    factor(
      priority,
      levels = c(
        "critical",
        "high",
        "medium",
        "locked"
      )
    ),
    process_group
  )

write_csv(
  process_summary,
  file.path(
    out_dir,
    "process_asset_summary.csv"
  )
)

cat(
  "\nProcess asset summary:\n"
)

print(
  process_summary,
  n = Inf,
  width = Inf
)

cat(
  "\nTop candidate assets:\n"
)

print(
  path_score |>
    slice_head(n = 60) |>
    select(
      root_name,
      relative_path,
      extension,
      size_mb,
      matched_processes,
      audit_score
    ),
  n = Inf,
  width = Inf
)

cat(
  "\nRDS predictor-column hits:\n"
)

print(
  rds_column_hits |>
    filter(
      keyword_priority %in%
        c(
          "critical",
          "high"
        )
    ) |>
    arrange(
      process_group,
      relative_path,
      column_name
    ) |>
    slice_head(n = 100),
  n = Inf,
  width = Inf
)

log_msg(
  "Legacy predictor asset audit complete: ",
  out_dir
)
