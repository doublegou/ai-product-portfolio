#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(tibble)
  library(scales)
})

sf::sf_use_s2(TRUE)

project_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

input_file <- file.path(
  project_dir,
  "data_processed/global/final_prediction",
  "map_geometry_ordflow5",
  "global_major_rivers_ordflow5.rds"
)

out_dir <- file.path(
  project_dir,
  "outputs/global/final_maps"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

if (!file.exists(input_file)) {
  stop(
    "Missing global map geometry: ",
    input_file
  )
}

cat("Reading global major-river geometry...\n")

rivers <- readRDS(input_file)

required_cols <- c(
  "rf_mean",
  "qrf_p80_width",
  "ORD_FLOW",
  "region"
)

missing_cols <- setdiff(
  required_cols,
  names(rivers)
)

if (length(missing_cols) > 0) {
  stop(
    "Missing columns: ",
    paste(missing_cols, collapse = ", ")
  )
}

if (nrow(rivers) != 856837) {
  stop(
    "Unexpected river count: ",
    nrow(rivers)
  )
}

rivers <- rivers %>%
  filter(
    is.finite(rf_mean),
    is.finite(qrf_p80_width),
    is.finite(ORD_FLOW)
  ) %>%
  mutate(
    map_linewidth = case_when(
      ORD_FLOW <= 2 ~ 0.42,
      ORD_FLOW == 3 ~ 0.28,
      ORD_FLOW == 4 ~ 0.16,
      TRUE          ~ 0.075
    )
  )

cat(
  "Map-ready reaches:",
  nrow(rivers),
  "\n"
)

# Robinson projection.
robinson_crs <- paste(
  "+proj=robin",
  "+lon_0=0",
  "+datum=WGS84",
  "+units=m",
  "+no_defs"
)

cat("Transforming rivers to Robinson projection...\n")

rivers_robin <- st_transform(
  rivers,
  crs = robinson_crs
)

rm(rivers)
invisible(gc())

# Build the land basemap from the existing HydroBASINS L6 polygons.
# This avoids dependencies on rnaturalearth or maps.

cat("Building HydroBASINS land basemap...\n")

basemap_regions <- c(
  "af", "ar", "as",
  "au", "eu", "gr",
  "na", "sa", "si"
)

world_parts <- lapply(
  basemap_regions,
  function(r) {

    basin_file <- file.path(
      project_dir,
      "data_raw/hydrosheds/HydroBASINS_global",
      paste0(
        "hybas_",
        r,
        "_lev06_v1c.shp"
      )
    )

    if (!file.exists(basin_file)) {
      stop(
        "Missing HydroBASINS file: ",
        basin_file
      )
    }

    cat(
      "Reading basemap region:",
      toupper(r),
      "\n"
    )

    x <- st_read(
      basin_file,
      quiet = TRUE
    )

    x <- st_transform(
      x,
      4326
    )

    x <- suppressWarnings(
      st_wrap_dateline(
        x,
        options = c(
          "WRAPDATELINE=YES",
          "DATELINEOFFSET=10"
        ),
        quiet = TRUE
      )
    )

    x <- st_make_valid(x)

    x <- x[
      !st_is_empty(x),
      ,
      drop = FALSE
    ]

    region_geometry <- st_union(
      st_geometry(x)
    )

    st_sf(
      region = r,
      geometry = region_geometry,
      crs = 4326
    )
  }
)

world <- do.call(
  rbind,
  world_parts
)

rm(
  world_parts
)

invisible(
  gc()
)

cat(
  "Transforming HydroBASINS basemap to Robinson projection...\n"
)

world <- st_transform(
  world,
  crs = robinson_crs
)

# Robust display limits prevent a few extreme reaches
# from compressing the colour scale.
sr_limits <- as.numeric(
  quantile(
    rivers_robin$rf_mean,
    probs = c(0.01, 0.99),
    na.rm = TRUE
  )
)

uncertainty_limits <- c(
  0,
  as.numeric(
    quantile(
      rivers_robin$qrf_p80_width,
      probs = 0.95,
      na.rm = TRUE
    )
  )
)

display_limits <- tibble(
  map = c(
    "rf_mean",
    "qrf_p80_width"
  ),
  lower_limit = c(
    sr_limits[1],
    uncertainty_limits[1]
  ),
  upper_limit = c(
    sr_limits[2],
    uncertainty_limits[2]
  ),
  limit_definition = c(
    "1st–99th percentile; extremes squished",
    "0–95th percentile; upper extremes squished"
  )
)

write_csv(
  display_limits,
  file.path(
    out_dir,
    "global_map_display_limits.csv"
  )
)

cat("\nDisplay limits:\n")
print(display_limits)

base_theme <- theme_void(
  base_size = 11
) +
  theme(
    plot.title = element_text(
      face = "bold",
      size = 15,
      hjust = 0
    ),
    plot.subtitle = element_text(
      size = 10.5,
      hjust = 0,
      margin = margin(
        b = 8
      )
    ),
    plot.caption = element_text(
      size = 8.5,
      colour = "grey35",
      hjust = 0,
      margin = margin(
        t = 8
      )
    ),
    legend.position = "bottom",
    legend.title = element_text(
      size = 10
    ),
    legend.text = element_text(
      size = 9
    ),
    legend.key.width = grid::unit(
      3.4,
      "cm"
    ),
    plot.margin = margin(
      10,
      12,
      8,
      12
    )
  )

# ------------------------------------------------------------
# Map 1: RF mean
# ------------------------------------------------------------

cat("\nBuilding RF mean map...\n")

p_sr <- ggplot() +
  geom_sf(
    data = world,
    fill = "grey96",
    colour = "grey72",
    linewidth = 0.16
  ) +
  geom_sf(
    data = rivers_robin,
    aes(
      colour = rf_mean,
      linewidth = map_linewidth
    ),
    alpha = 0.96,
    show.legend = c(
      colour = TRUE,
      linewidth = FALSE
    )
  ) +
  scale_linewidth_identity() +
  scale_colour_viridis_c(
    option = "C",
    limits = sr_limits,
    oob = squish,
    guide = guide_colourbar(
      title.position = "top",
      title.hjust = 0.5,
      barheight = grid::unit(
        0.34,
        "cm"
      )
    )
  ) +
  coord_sf(
    datum = NA,
    expand = FALSE
  ) +
  labs(
    title = expression(
      paste(
        "Predicted global river-water ",
        {}^{87},
        "Sr/",
        {}^{86},
        "Sr"
      )
    ),
    subtitle = paste0(
      "Random-forest mean predictions; ",
      "HydroRIVERS reaches with ORD_FLOW ≤ 5"
    ),
    colour = expression(
      paste(
        "Predicted ",
        {}^{87},
        "Sr/",
        {}^{86},
        "Sr"
      )
    ),
    caption = paste0(
      "Colour limits show the 1st–99th percentile; ",
      "values beyond the limits are retained and squished. ",
      "Line width reflects HydroRIVERS flow-order class."
    )
  ) +
  base_theme

sr_png <- file.path(
  out_dir,
  "global_river_Sr_RF_mean_ordflow5_preview.png"
)

ggsave(
  filename = sr_png,
  plot = p_sr,
  width = 13,
  height = 7.4,
  dpi = 240,
  bg = "white",
  limitsize = FALSE
)

cat(
  "Saved:",
  sr_png,
  "\n"
)

rm(p_sr)
invisible(gc())

# ------------------------------------------------------------
# Map 2: model-based uncertainty
# ------------------------------------------------------------

cat("\nBuilding uncertainty map...\n")

p_uncertainty <- ggplot() +
  geom_sf(
    data = world,
    fill = "grey96",
    colour = "grey72",
    linewidth = 0.16
  ) +
  geom_sf(
    data = rivers_robin,
    aes(
      colour = qrf_p80_width,
      linewidth = map_linewidth
    ),
    alpha = 0.96,
    show.legend = c(
      colour = TRUE,
      linewidth = FALSE
    )
  ) +
  scale_linewidth_identity() +
  scale_colour_viridis_c(
    option = "magma",
    direction = 1,
    limits = uncertainty_limits,
    oob = squish,
    guide = guide_colourbar(
      title.position = "top",
      title.hjust = 0.5,
      barheight = grid::unit(
        0.34,
        "cm"
      )
    )
  ) +
  coord_sf(
    datum = NA,
    expand = FALSE
  ) +
  labs(
    title = "Model-based predictive uncertainty",
    subtitle = paste0(
      "Width of the QRF p10–p90 predictive range; ",
      "HydroRIVERS reaches with ORD_FLOW ≤ 5"
    ),
    colour = expression(
      paste(
        "p90 - p10 in ",
        {}^{87},
        "Sr/",
        {}^{86},
        "Sr"
      )
    ),
    caption = paste0(
      "Colour limits show 0–95th percentile; ",
      "larger values indicate wider model-based ",
      "predictive quantile ranges."
    )
  ) +
  base_theme

uncertainty_png <- file.path(
  out_dir,
  paste0(
    "global_river_Sr_QRF_",
    "p80_width_ordflow5_preview.png"
  )
)

ggsave(
  filename = uncertainty_png,
  plot = p_uncertainty,
  width = 13,
  height = 7.4,
  dpi = 240,
  bg = "white",
  limitsize = FALSE
)

cat(
  "Saved:",
  uncertainty_png,
  "\n"
)

cat(
  "\nGLOBAL RIVER MAP PREVIEWS FINISHED\n"
)
