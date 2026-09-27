file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this file with Rscript.", call. = FALSE)
}
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

site_path <- river_sr_path(context, context$config$output$candidate_sites)
output_path <- river_sr_path(context, context$config$output$basin_assignment)
scope_path <- river_sr_path(context, context$config$output$basin_scope)
raw_root <- river_sr_path(context, "data/raw/features/hydrography/hydrobasins_l6")

river_sr_assert(file.exists(site_path), paste("Run step 01 first; missing:", site_path))

suppressPackageStartupMessages(library(sf))
sf::sf_use_s2(TRUE)

region_codes <- c("af", "ar", "as", "au", "eu", "gr", "na", "sa", "si")
basin_parts <- lapply(region_codes, function(region) {
  shapefile <- file.path(raw_root, region, paste0("hybas_", region, "_lev06_v1c.shp"))
  river_sr_assert(file.exists(shapefile), paste("Missing HydroBASINS file:", shapefile))
  x <- sf::st_read(shapefile, quiet = TRUE)[, c("HYBAS_ID", "NEXT_DOWN"), drop = FALSE]
  if (sf::st_crs(x)$epsg != 4326L) {
    x <- sf::st_transform(x, 4326)
  }
  x <- sf::st_make_valid(x)
  x$basin_region <- region
  x
})
basins <- do.call(rbind, basin_parts)
river_sr_assert(!anyDuplicated(basins$HYBAS_ID), "Combined HydroBASINS contains duplicated HYBAS_ID values.")

sites <- data.table::as.data.table(readRDS(site_path))
points <- sf::st_as_sf(
  sites,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
)

basins_equal_area <- sf::st_transform(basins, 6933)
basin_area_km2 <- as.numeric(sf::st_area(basins_equal_area)) / 1e6
choose_smallest <- function(indices) {
  if (length(indices) == 0L) return(NA_integer_)
  indices[[which.min(basin_area_km2[indices])]]
}

assigned <- rep(NA_integer_, nrow(points))
method <- rep("unmatched", nrow(points))
nearest_distance_km <- rep(NA_real_, nrow(points))

within <- sf::st_within(points, basins, sparse = TRUE)
for (i in seq_along(within)) {
  if (length(within[[i]]) == 1L) {
    assigned[[i]] <- within[[i]]
    method[[i]] <- "within"
  } else if (length(within[[i]]) > 1L) {
    assigned[[i]] <- choose_smallest(within[[i]])
    method[[i]] <- "within_multiple_smallest"
  }
}

unmatched <- which(is.na(assigned))
if (length(unmatched) > 0L) {
  intersects <- sf::st_intersects(points[unmatched, ], basins, sparse = TRUE)
  for (j in seq_along(unmatched)) {
    i <- unmatched[[j]]
    if (length(intersects[[j]]) == 1L) {
      assigned[[i]] <- intersects[[j]]
      method[[i]] <- "boundary_intersects"
    } else if (length(intersects[[j]]) > 1L) {
      assigned[[i]] <- choose_smallest(intersects[[j]])
      method[[i]] <- "boundary_multiple_smallest"
    }
  }
}

unmatched <- which(is.na(assigned))
if (length(unmatched) > 0L) {
  unmatched_equal_area <- sf::st_transform(points[unmatched, ], 6933)
  nearest <- sf::st_nearest_feature(unmatched_equal_area, basins_equal_area)
  distance <- as.numeric(sf::st_distance(
    unmatched_equal_area,
    basins_equal_area[nearest, ],
    by_element = TRUE
  )) / 1000
  nearest_distance_km[unmatched] <- distance
  accepted <- is.finite(distance) & distance <= context$config$rules$nearest_basin_limit_km
  assigned[unmatched[accepted]] <- nearest[accepted]
  method[unmatched[accepted]] <- "nearest_within_25km"
}

assignment <- data.table::data.table(
  site_id = sites$site_id,
  current_hybas_id = ifelse(is.na(assigned), NA_character_, sprintf("%.0f", basins$HYBAS_ID[assigned])),
  basin_region = ifelse(is.na(assigned), NA_character_, basins$basin_region[assigned]),
  basin_assignment_method = method,
  nearest_basin_distance_km = nearest_distance_km
)

assignment[, `:=`(
  legacy_hybas_id = NA_character_,
  hybrid_hybas_id = current_hybas_id,
  hybas_source = "current"
)]
data.table::setorder(assignment, site_id)

network <- data.table::as.data.table(sf::st_drop_geometry(basins))[, .(
  HYBAS_ID,
  NEXT_DOWN,
  basin_region
)]
scope_ids <- river_sr_upstream_scope(network, assignment$current_hybas_id)
network[, hybas_id := sprintf("%.0f", as.numeric(HYBAS_ID))]
scope <- network[hybas_id %in% scope_ids]
river_sr_assert(
  all(assignment$current_hybas_id[!is.na(assignment$current_hybas_id)] %in% scope$hybas_id),
  "The upstream basin scope omitted one or more assigned sites."
)

river_sr_save_rds(assignment, output_path)
river_sr_save_rds(scope, scope_path)
message(sprintf(
  "02 complete: assigned %d/%d sites; retained %d target/upstream L6 basins: %s",
  sum(!is.na(assignment$current_hybas_id)), nrow(assignment), nrow(scope), output_path
))
