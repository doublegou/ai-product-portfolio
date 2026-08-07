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

audit_dir <- file.path(
  project_root(),
  "outputs/legacy_asset_audit"
)

out_dir <- file.path(
  project_root(),
  "outputs/verified_asset_inventory"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

all_files_path <- file.path(
  audit_dir,
  "all_files.csv"
)

stop_missing(
  all_files_path,
  "Run legacy asset audit first."
)

all_files <- read_csv(
  all_files_path,
  show_col_types = FALSE
)

legacy_table_path <- file.path(
  Sys.getenv("HOME"),
  paste0(
    "projects/sr_global/data_processed/global/",
    "global_model_sites_5km_with_geology_",
    "climate_terrain_soil_complete.rds"
  )
)

stop_missing(
  legacy_table_path,
  "Legacy complete predictor table not found."
)

legacy <- readRDS(
  legacy_table_path
)

if (!is.data.frame(legacy)) {
  stop("Legacy predictor object is not a data frame.")
}

# ------------------------------------------------------------
# 1. Verify reusable columns in the legacy predictor table
# ------------------------------------------------------------

column_groups <- tribble(
  ~feature_group, ~column_regex,

  "local_lithology",
  "^local_geo_.*_frac$",

  "upstream_lithology",
  "^up_geo_.*_frac$",

  "local_climate",
  "^local_(bio[0-9]+|ai_ratio|et0_mm)",

  "upstream_climate",
  "^up_(bio[0-9]+|ai_ratio|et0_mm)",

  "local_terrain",
  "^local_(elevation|slope|relief|rugged)",

  "upstream_terrain",
  "^up_(elevation|slope|relief|rugged)",

  "local_soil",
  "^local_soil_",

  "upstream_soil",
  "^up_soil_",

  "river_network",
  paste0(
    "^(DIS_AV_CMS|UPLAND_SKM|CATCH_SKM|",
    "LENGTH_KM|DIST_DN_KM|DIST_UP_KM|",
    "ORD_STRA|ORD_CLAS|ORD_FLOW)$"
  )
)

verified_columns <- map_dfr(
  seq_len(nrow(column_groups)),
  function(i) {
    matching_columns <- names(legacy)[
      str_detect(
        names(legacy),
        regex(
          column_groups$column_regex[i],
          ignore_case = TRUE
        )
      )
    ]

    if (length(matching_columns) == 0L) {
      return(tibble())
    }

    tibble(
      feature_group =
        column_groups$feature_group[i],

      column_name =
        matching_columns,

      storage_class = vapply(
        legacy[matching_columns],
        function(x) {
          paste(
            class(x),
            collapse = ";"
          )
        },
        character(1)
      ),

      nonmissing_n = vapply(
        legacy[matching_columns],
        function(x) {
          sum(!is.na(x))
        },
        integer(1)
      ),

      unique_n = vapply(
        legacy[matching_columns],
        function(x) {
          dplyr::n_distinct(
            x,
            na.rm = TRUE
          )
        },
        integer(1)
      )
    ) |>
      mutate(
        n_rows = nrow(legacy),
        nonmissing_fraction =
          nonmissing_n / n_rows
      )
  }
) |>
  arrange(
    feature_group,
    column_name
  )

write_csv(
  verified_columns,
  file.path(
    out_dir,
    "verified_reusable_columns.csv"
  )
)

# ------------------------------------------------------------
# 2. Exact file-pattern search
#
# Deliberately exclude generic "sr87" and "isoscape":
# these identify the response, not bedrock Sr.
# ------------------------------------------------------------

asset_definitions <- tribble(
  ~input_name, ~file_regex, ~priority,

  "bedrock_sr",
  paste0(
    "bedrock[_ -]?sr|",
    "bedrock.*strontium|",
    "bataille|",
    "radiogenic[_ -]?(map|raster|grid)"
  ),
  "critical",

  "geological_age",
  paste0(
    "geological[_ -]?age|",
    "geology[_ -]?age|",
    "rock[_ -]?age|",
    "bedrock[_ -]?age"
  ),
  "critical",

  "runoff",
  paste0(
    "(^|[/_.-])runoff([/_.-]|$)|",
    "water[_ -]?yield"
  ),
  "critical",

  "glacier",
  paste0(
    "glacier|glaciated|",
    "permafrost|",
    "snow[_ -]?fraction|",
    "ice[_ -]?cover"
  ),
  "critical",

  "relief_slope",
  paste0(
    "relief|rugged|",
    "(^|[/_.-])slope([/_.-]|$)"
  ),
  "critical",

  "elevation_dem",
  paste0(
    "elevation|",
    "(^|[/_.-])dem([/_.-]|$)|",
    "worldclim_elevation"
  ),
  "available",

  "baseflow",
  "base[_ -]?flow|baseflow",
  "high",

  "permeability",
  "permeab",
  "high",

  "porosity",
  "porosity",
  "medium",

  "groundwater_recharge",
  "groundwater.*recharge|recharge.*groundwater",
  "medium",

  "lithology_glim",
  "glim|litholog",
  "available",

  "aridity_et0",
  "aridity|global-ai|annual_et0|ai_v31",
  "available",

  "soil_clay",
  "soil|clay",
  "available",

  "hydrorivers",
  "hydroriver|hydrobasin",
  "available"
)

spatial_extensions <- c(
  "tif",
  "tiff",
  "vrt",
  "nc",
  "grd",
  "bil",
  "img",
  "gpkg",
  "shp",
  "rds",
  "csv"
)

verified_assets <- map_dfr(
  seq_len(nrow(asset_definitions)),
  function(i) {
    hits <- all_files |>
      filter(
        root_name ==
          "legacy_project",

        extension %in%
          spatial_extensions,

        str_detect(
          str_to_lower(relative_path),
          regex(
            asset_definitions$file_regex[i],
            ignore_case = TRUE
          )
        )
      )

    if (nrow(hits) == 0L) {
      return(
        tibble(
          input_name =
            asset_definitions$input_name[i],

          priority =
            asset_definitions$priority[i],

          relative_path =
            NA_character_,

          extension =
            NA_character_,

          size_mb =
            NA_real_
        )
      )
    }

    hits |>
      transmute(
        input_name =
          asset_definitions$input_name[i],

        priority =
          asset_definitions$priority[i],

        relative_path,
        extension,
        size_mb
      )
  }
) |>
  arrange(
    factor(
      priority,
      levels = c(
        "critical",
        "high",
        "medium",
        "available"
      )
    ),
    input_name,
    relative_path
  )

write_csv(
  verified_assets,
  file.path(
    out_dir,
    "verified_external_assets.csv"
  )
)

asset_status <- verified_assets |>
  group_by(
    input_name,
    priority
  ) |>
  summarise(
    n_candidate_files = sum(
      !is.na(relative_path)
    ),

    examples = paste(
      head(
        relative_path[
          !is.na(relative_path)
        ],
        5
      ),
      collapse = "; "
    ),

    .groups = "drop"
  ) |>
  mutate(
    verified_status = case_when(
      n_candidate_files > 0L ~
        "candidate_asset_found",

      TRUE ~
        "no_verified_asset"
    )
  ) |>
  arrange(
    factor(
      priority,
      levels = c(
        "critical",
        "high",
        "medium",
        "available"
      )
    ),
    input_name
  )

write_csv(
  asset_status,
  file.path(
    out_dir,
    "verified_asset_status.csv"
  )
)

# ------------------------------------------------------------
# 3. Locate genuine upstream-aggregation scripts
# ------------------------------------------------------------

script_files <- all_files |>
  filter(
    root_name ==
      "legacy_project",

    extension %in%
      c(
        "r",
        "rmd",
        "py",
        "sh"
      ),

    size_mb <= 5,

    !str_detect(
      relative_path,
      regex(
        "checkpoint|archive|backup",
        ignore_case = TRUE
      )
    )
  )

aggregation_pattern <- paste0(
  "l6_glim_local_upstream|",
  "climate_terrain_l6_by_region|",
  "soil_l6_by_region|",
  "hydrorivers_region_manifest|",
  "upstream.*coverage|",
  "upstream.*weight|",
  "flow_accum|",
  "flowacc|",
  "exact_extract|",
  "weighted.mean"
)

read_matching_lines <- function(
    path,
    relative_path
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

  hit_index <- which(
    str_detect(
      content,
      regex(
        aggregation_pattern,
        ignore_case = TRUE
      )
    )
  )

  if (length(hit_index) == 0L) {
    return(tibble())
  }

  tibble(
    relative_path = relative_path,
    line_number = hit_index,
    line_text = str_trim(
      content[hit_index]
    )
  )
}

aggregation_script_hits <- map2_dfr(
  script_files$path,
  script_files$relative_path,
  read_matching_lines
) |>
  distinct() |>
  arrange(
    relative_path,
    line_number
  )

write_csv(
  aggregation_script_hits,
  file.path(
    out_dir,
    "legacy_aggregation_script_hits.csv"
  )
)

script_summary <- aggregation_script_hits |>
  count(
    relative_path,
    name = "n_relevant_lines"
  ) |>
  arrange(
    desc(n_relevant_lines),
    relative_path
  )

write_csv(
  script_summary,
  file.path(
    out_dir,
    "legacy_aggregation_script_summary.csv"
  )
)

# ------------------------------------------------------------
# 4. Final reuse/gap summary
# ------------------------------------------------------------

reusable_summary <- verified_columns |>
  count(
    feature_group,
    name = "n_columns"
  ) |>
  summarise(
    input_name = feature_group,
    evidence_type =
      "legacy_site_columns",
    n_items = n_columns,
    .by = feature_group
  ) |>
  select(
    -feature_group
  )

external_summary <- asset_status |>
  transmute(
    input_name,
    evidence_type =
      "legacy_external_files",
    n_items =
      n_candidate_files
  )

final_summary <- bind_rows(
  reusable_summary,
  external_summary
) |>
  arrange(
    input_name,
    evidence_type
  )

write_csv(
  final_summary,
  file.path(
    out_dir,
    "verified_reuse_and_gap_summary.csv"
  )
)

cat("\nVerified external asset status:\n")

print(
  asset_status,
  n = Inf,
  width = Inf
)

cat("\nVerified reusable legacy columns:\n")

print(
  verified_columns |>
    count(
      feature_group,
      name = "n_columns"
    ),
  n = Inf,
  width = Inf
)

cat("\nLikely upstream-aggregation scripts:\n")

print(
  script_summary |>
    slice_head(n = 30),
  n = Inf,
  width = Inf
)

log_msg(
  "Verified asset inventory complete: ",
  out_dir
)
