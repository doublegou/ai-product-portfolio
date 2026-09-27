#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(tibble)
})

sf::sf_use_s2(TRUE)

site_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

site_file <- file.path(
  site_dir,
  "data_processed/global/global_model_sites_5km_main_all_sites.rds"
)

geo_dir <- file.path(
  site_dir,
  "data_processed/global/glim_l6_by_region"
)

basin_dir <- file.path(
  site_dir,
  "data_raw/hydrosheds/HydroBASINS_global"
)

out_data <- file.path(
  site_dir,
  "data_processed/global"
)

out_qc <- file.path(
  site_dir,
  "outputs/global/glim_l6_qc"
)

dir.create(out_data, recursive = TRUE, showWarnings = FALSE)
dir.create(out_qc, recursive = TRUE, showWarnings = FALSE)

regions <- c(
  "af", "ar", "as", "au", "eu",
  "gr", "na", "sa", "si"
)

sites <- readRDS(site_file)

required_site_cols <- c(
  "site_id",
  "longitude",
  "latitude",
  "region",
  "sr"
)

missing_site_cols <- setdiff(
  required_site_cols,
  names(sites)
)

if (length(missing_site_cols) > 0) {
  stop(
    "Missing site columns: ",
    paste(missing_site_cols, collapse = ", ")
  )
}

sites$region <- as.character(sites$region)

site_sf <- st_as_sf(
  sites,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
)

assignment_list <- list()

for (r in regions) {

  message("Assigning sites to L6 basins: ", r)

  region_index <- which(
    sites$region == r
  )

  if (length(region_index) == 0) {
    message("No sites in region: ", r)
    next
  }

  basin_file <- file.path(
    basin_dir,
    paste0(
      "hybas_",
      r,
      "_lev06_v1c.shp"
    )
  )

  if (!file.exists(basin_file)) {
    stop("Missing basin file: ", basin_file)
  }

  basins <- st_read(
    basin_file,
    quiet = TRUE
  ) %>%
    st_transform(4326)

  basins <- suppressWarnings(
    st_wrap_dateline(
      basins,
      options = c(
        "WRAPDATELINE=YES",
        "DATELINEOFFSET=10"
      ),
      quiet = TRUE
    )
  )

  basins <- st_make_valid(basins)

  basins <- basins[
    !st_is_empty(basins),
    ,
    drop = FALSE
  ]

  basin_attributes <- basins %>%
    st_drop_geometry() %>%
    transmute(
      HYBAS_ID = HYBAS_ID,
      hybas_key = sprintf(
        "%.0f",
        as.numeric(HYBAS_ID)
      ),
      l6_NEXT_DOWN = NEXT_DOWN,
      l6_MAIN_BAS = MAIN_BAS,
      l6_SUB_AREA = SUB_AREA,
      l6_UP_AREA = UP_AREA,
      l6_PFAF_ID = PFAF_ID
    )

  points_r <- site_sf[
    region_index,
    ,
    drop = FALSE
  ]

  intersections <- st_intersects(
    points_r,
    basins
  )

  basin_index <- vapply(
    intersections,
    function(z) {
      if (length(z) == 0) {
        NA_integer_
      } else {
        z[[1]]
      }
    },
    integer(1)
  )

  assignment_method <- ifelse(
    is.na(basin_index),
    "nearest_l6",
    "within_l6"
  )

  assignment_distance_m <- rep(
    0,
    length(region_index)
  )

  unmatched <- which(
    is.na(basin_index)
  )

  if (length(unmatched) > 0) {

    nearest_index <- st_nearest_feature(
      points_r[unmatched, ],
      basins
    )

    nearest_distance <- as.numeric(
      st_distance(
        points_r[unmatched, ],
        basins[nearest_index, ],
        by_element = TRUE
      )
    )

    basin_index[unmatched] <- nearest_index

    assignment_distance_m[unmatched] <-
      nearest_distance
  }

  assigned_attributes <- basin_attributes[
    basin_index,
    ,
    drop = FALSE
  ]

  assignment_list[[r]] <- bind_cols(
    tibble(
      site_id = sites$site_id[
        region_index
      ],
      region = r,
      l6_assignment_method =
        assignment_method,
      l6_assignment_distance_m =
        assignment_distance_m
    ),
    assigned_attributes
  )
}

assignments <- bind_rows(
  assignment_list
)

if (nrow(assignments) != nrow(sites)) {
  stop(
    "Site assignment row count mismatch: ",
    nrow(assignments),
    " versus ",
    nrow(sites)
  )
}

geo_files <- file.path(
  geo_dir,
  paste0(
    "l6_glim_local_upstream_",
    regions,
    ".rds"
  )
)

missing_geo_files <- geo_files[
  !file.exists(geo_files)
]

if (length(missing_geo_files) > 0) {
  stop(
    "Missing geology files: ",
    paste(missing_geo_files, collapse = ", ")
  )
}

geology <- bind_rows(
  lapply(
    geo_files,
    readRDS
  )
) %>%
  mutate(
    region = as.character(region),
    hybas_key = sprintf(
      "%.0f",
      as.numeric(HYBAS_ID)
    )
  )

geology_predictor_cols <- c(
  grep(
    "^local_geo_.*_frac$",
    names(geology),
    value = TRUE
  ),
  grep(
    "^up_geo_.*_frac$",
    names(geology),
    value = TRUE
  ),
  "local_total_extracted_area_km2",
  "local_lith_area_km2",
  "local_glim_coverage_ratio",
  "local_water_ice_frac_all",
  "local_no_data_frac_all",
  "up_total_extracted_area_km2",
  "up_lith_area_km2",
  "up_glim_coverage_ratio",
  "up_water_ice_frac_all",
  "up_no_data_frac_all"
)

geology_join <- geology %>%
  select(
    region,
    hybas_key,
    all_of(
      geology_predictor_cols
    )
  )

sites_geo <- sites %>%
  left_join(
    assignments,
    by = c(
      "site_id",
      "region"
    )
  ) %>%
  left_join(
    geology_join,
    by = c(
      "region",
      "hybas_key"
    )
  )

local_fraction_cols <- grep(
  "^local_geo_.*_frac$",
  names(sites_geo),
  value = TRUE
)

up_fraction_cols <- grep(
  "^up_geo_.*_frac$",
  names(sites_geo),
  value = TRUE
)

sites_geo$local_geo_fraction_sum <-
  rowSums(
    sites_geo[
      ,
      local_fraction_cols,
      drop = FALSE
    ],
    na.rm = FALSE
  )

sites_geo$up_geo_fraction_sum <-
  rowSums(
    sites_geo[
      ,
      up_fraction_cols,
      drop = FALSE
    ],
    na.rm = FALSE
  )

sites_geo <- sites_geo %>%
  mutate(
    l6_assignment_ok =
      is.finite(
        l6_assignment_distance_m
      ) &
      l6_assignment_distance_m <= 10000,

    local_glim_usable =
      l6_assignment_ok &
      is.finite(local_lith_area_km2) &
      local_lith_area_km2 > 0 &
      is.finite(local_geo_fraction_sum) &
      abs(local_geo_fraction_sum - 1) <
        1e-6,

    upstream_glim_usable =
      l6_assignment_ok &
      is.finite(up_lith_area_km2) &
      up_lith_area_km2 > 0 &
      is.finite(up_geo_fraction_sum) &
      abs(up_geo_fraction_sum - 1) <
        1e-6
  )

saveRDS(
  sites_geo,
  file.path(
    out_data,
    "global_model_sites_5km_with_l6_glim.rds"
  )
)

write_csv(
  sites_geo,
  file.path(
    out_qc,
    "global_model_sites_5km_with_l6_glim.csv"
  )
)

sites_geo_complete <- sites_geo %>%
  filter(
    local_glim_usable,
    upstream_glim_usable
  )

saveRDS(
  sites_geo_complete,
  file.path(
    out_data,
    "global_model_sites_5km_with_l6_glim_complete.rds"
  )
)

assignment_summary <- tibble(
  metric = c(
    "all_sites",
    "within_l6_assignment",
    "nearest_l6_assignment",
    "assignment_within_5km",
    "assignment_within_10km",
    "local_glim_usable",
    "upstream_glim_usable",
    "both_local_and_upstream_usable"
  ),
  value = c(
    nrow(sites_geo),
    sum(
      sites_geo$l6_assignment_method ==
        "within_l6"
    ),
    sum(
      sites_geo$l6_assignment_method ==
        "nearest_l6"
    ),
    sum(
      sites_geo$l6_assignment_distance_m <=
        5000,
      na.rm = TRUE
    ),
    sum(
      sites_geo$l6_assignment_distance_m <=
        10000,
      na.rm = TRUE
    ),
    sum(
      sites_geo$local_glim_usable,
      na.rm = TRUE
    ),
    sum(
      sites_geo$upstream_glim_usable,
      na.rm = TRUE
    ),
    nrow(sites_geo_complete)
  )
)

regional_summary <- sites_geo %>%
  group_by(region) %>%
  summarise(
    n_sites = n(),
    n_within_l6 = sum(
      l6_assignment_method == "within_l6"
    ),
    n_nearest_l6 = sum(
      l6_assignment_method == "nearest_l6"
    ),
    median_assignment_distance_m =
      median(
        l6_assignment_distance_m,
        na.rm = TRUE
      ),
    max_assignment_distance_m =
      max(
        l6_assignment_distance_m,
        na.rm = TRUE
      ),
    n_local_glim_usable =
      sum(
        local_glim_usable,
        na.rm = TRUE
      ),
    n_upstream_glim_usable =
      sum(
        upstream_glim_usable,
        na.rm = TRUE
      ),
    .groups = "drop"
  ) %>%
  arrange(region)

write_csv(
  assignment_summary,
  file.path(
    out_qc,
    "global_site_l6_glim_assignment_summary.csv"
  )
)

write_csv(
  regional_summary,
  file.path(
    out_qc,
    "global_site_l6_glim_assignment_by_region.csv"
  )
)

write_csv(
  sites_geo %>%
    filter(
      !local_glim_usable |
        !upstream_glim_usable
    ) %>%
    select(
      site_id,
      longitude,
      latitude,
      region,
      sr,
      HYBAS_ID,
      l6_assignment_method,
      l6_assignment_distance_m,
      local_glim_coverage_ratio,
      up_glim_coverage_ratio,
      local_water_ice_frac_all,
      up_water_ice_frac_all,
      local_no_data_frac_all,
      up_no_data_frac_all,
      local_glim_usable,
      upstream_glim_usable
    ),
  file.path(
    out_qc,
    "global_sites_without_complete_l6_glim.csv"
  )
)

cat("\nGlobal L6 GLiM assignment summary:\n")
print(assignment_summary)

cat("\nRegional L6 GLiM assignment summary:\n")
print(
  regional_summary,
  n = Inf,
  width = Inf
)

cat("\nLocal fraction sums:\n")
print(
  summary(
    sites_geo$local_geo_fraction_sum
  )
)

cat("\nUpstream fraction sums:\n")
print(
  summary(
    sites_geo$up_geo_fraction_sum
  )
)

cat(
  "\nGlobal site-to-L6 geology attachment finished.\n"
)
