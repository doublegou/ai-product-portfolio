file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this file with Rscript.", call. = FALSE)
}
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

site_path <- river_sr_path(context, context$config$output$candidate_sites)
output_path <- river_sr_path(context, context$config$output$hydrology)
river_path <- river_sr_path(
  context,
  "data/raw/features/hydrography/hydrorivers_v10/HydroRIVERS_v10_shp/HydroRIVERS_v10.shp"
)
river_sr_assert(file.exists(site_path), paste("Run step 01 first; missing:", site_path))
river_sr_assert(file.exists(river_path), paste("Missing HydroRIVERS shapefile:", river_path))

suppressPackageStartupMessages(library(sf))
sf::sf_use_s2(TRUE)

sites <- data.table::as.data.table(readRDS(site_path))
sites[, `:=`(
  tile_x = floor((longitude + 180) / 5),
  tile_y = floor((latitude + 90) / 5)
)]
tile_ids <- unique(sites[, .(tile_x, tile_y)])
data.table::setorder(tile_ids, tile_y, tile_x)

query <- paste(
  "SELECT HYRIV_ID, NEXT_DOWN, MAIN_RIV, LENGTH_KM, DIST_DN_KM, DIST_UP_KM,",
  "CATCH_SKM, UPLAND_SKM, DIS_AV_CMS, ORD_STRA, ORD_CLAS, ORD_FLOW",
  "FROM HydroRIVERS_v10"
)

snap_tile <- function(tile_x, tile_y) {
  index <- which(sites$tile_x == tile_x & sites$tile_y == tile_y)
  tile_sites <- sites[index]
  pad <- 1
  bbox <- sf::st_bbox(c(
    xmin = max(-180, min(tile_sites$longitude) - pad),
    ymin = max(-90, min(tile_sites$latitude) - pad),
    xmax = min(180, max(tile_sites$longitude) + pad),
    ymax = min(90, max(tile_sites$latitude) + pad)
  ), crs = sf::st_crs(4326))
  filter_wkt <- sf::st_as_text(sf::st_as_sfc(bbox))
  rivers <- sf::st_read(
    river_path,
    query = query,
    wkt_filter = filter_wkt,
    quiet = TRUE
  )
  if (nrow(rivers) == 0L) {
    return(data.table::data.table(
      site_id = tile_sites$site_id,
      snap_distance_m = NA_real_,
      snapped_longitude = NA_real_,
      snapped_latitude = NA_real_,
      HYRIV_ID = NA_real_, NEXT_DOWN = NA_real_, MAIN_RIV = NA_real_,
      LENGTH_KM = NA_real_, DIST_DN_KM = NA_real_, DIST_UP_KM = NA_real_,
      CATCH_SKM = NA_real_, UPLAND_SKM = NA_real_, DIS_AV_CMS = NA_real_,
      ORD_STRA = NA_real_, ORD_CLAS = NA_real_, ORD_FLOW = NA_real_
    ))
  }

  points <- sf::st_as_sf(
    tile_sites,
    coords = c("longitude", "latitude"),
    crs = 4326,
    remove = FALSE
  )
  nearest <- sf::st_nearest_feature(points, rivers)
  distance_m <- as.numeric(sf::st_distance(points, rivers[nearest, ], by_element = TRUE))

  # The legacy P0 spatial coordinates represented the selected reach itself.
  # For a line, GEOS point-on-surface returns the interior HydroRIVERS vertex
  # used by the historical workflow.
  reach_points <- suppressWarnings(sf::st_point_on_surface(rivers[nearest, ]))
  snapped_xy <- sf::st_coordinates(reach_points)[, c("X", "Y"), drop = FALSE]

  attributes <- data.table::as.data.table(sf::st_drop_geometry(rivers[nearest, ]))
  data.table::data.table(
    site_id = tile_sites$site_id,
    snap_distance_m = distance_m,
    snapped_longitude = snapped_xy[, 1L],
    snapped_latitude = snapped_xy[, 2L],
    attributes
  )
}

parts <- vector("list", nrow(tile_ids))
for (i in seq_len(nrow(tile_ids))) {
  message(sprintf("HydroRIVERS tile %d/%d", i, nrow(tile_ids)))
  parts[[i]] <- snap_tile(tile_ids$tile_x[[i]], tile_ids$tile_y[[i]])
}
hydrology <- data.table::rbindlist(parts, use.names = TRUE)
data.table::setorder(hydrology, site_id)

lon_rad <- hydrology$snapped_longitude * pi / 180
lat_rad <- hydrology$snapped_latitude * pi / 180
hydrology[, `:=`(
  p0__sp_x = cos(lat_rad) * cos(lon_rad),
  p0__sp_y = cos(lat_rad) * sin(lon_rad),
  p0__sp_z = sin(lat_rad),
  p0__log_DIS_AV_CMS = log1p(as.numeric(DIS_AV_CMS)),
  p0__log_UPLAND_SKM = log1p(as.numeric(UPLAND_SKM)),
  p0__log_CATCH_SKM = log1p(as.numeric(CATCH_SKM)),
  p0__log_LENGTH_KM = log1p(as.numeric(LENGTH_KM)),
  p0__log_DIST_DN_KM = log1p(as.numeric(DIST_DN_KM)),
  p0__log_DIST_UP_KM = log1p(as.numeric(DIST_UP_KM)),
  p0__ORD_STRA = as.numeric(ORD_STRA),
  p0__ORD_CLAS = as.numeric(ORD_CLAS),
  p0__ORD_FLOW = as.numeric(ORD_FLOW)
)]

p0_hydrology <- c(
  "p0__sp_x", "p0__sp_y", "p0__sp_z", "p0__log_DIS_AV_CMS",
  "p0__log_UPLAND_SKM", "p0__log_CATCH_SKM", "p0__log_LENGTH_KM",
  "p0__log_DIST_DN_KM", "p0__log_DIST_UP_KM", "p0__ORD_STRA",
  "p0__ORD_CLAS", "p0__ORD_FLOW"
)
outside_limit <- !is.finite(hydrology$snap_distance_m) |
  hydrology$snap_distance_m > context$config$rules$snap_limit_m
hydrology[outside_limit, (p0_hydrology) := NA_real_]

river_sr_assert(!anyDuplicated(hydrology$site_id), "Hydrology output contains duplicated site IDs.")
river_sr_assert(nrow(hydrology) == nrow(sites), "Hydrology extraction changed the candidate-site count.")
river_sr_save_rds(hydrology, output_path)
message(sprintf(
  "03 complete: %d/%d sites snapped within %.0f m: %s",
  sum(!outside_limit), nrow(hydrology), context$config$rules$snap_limit_m, output_path
))
