file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this file with Rscript.", call. = FALSE)
}
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

assignment_path <- river_sr_path(context, context$config$output$basin_assignment)
scope_path <- river_sr_path(context, context$config$output$basin_scope)
output_path <- river_sr_path(context, context$config$output$geology)
glim_path <- river_sr_path(
  context,
  "data/raw/features/geology/glim_v1/gridded_0p5deg/glim_wgs84_0point5deg.txt.asc"
)
river_sr_assert(file.exists(assignment_path), paste("Run step 02 first; missing:", assignment_path))
river_sr_assert(file.exists(scope_path), paste("Run step 02 first; missing:", scope_path))
river_sr_assert(file.exists(glim_path), paste("Missing GLiM raster:", glim_path))

suppressPackageStartupMessages({
  library(sf)
  library(terra)
})
terra::terraOptions(memfrac = 0.70, progress = 1)

glim <- terra::rast(glim_path)
names(glim) <- "glim_class"
cell_area <- terra::cellSize(glim, unit = "km")
names(cell_area) <- "cell_area_km2"
glim_stack <- c(glim, cell_area)
scope <- data.table::as.data.table(readRDS(scope_path))

class_group <- c(
  "1" = "unconsolidated", "2" = "volcanic", "3" = "siliciclastic",
  "4" = "plutonic", "5" = "mixed_sedimentary", "6" = "carbonate",
  "7" = "volcanic", "8" = "metamorphic", "9" = "plutonic",
  "10" = "volcanic", "11" = "water_ice", "12" = "volcanic",
  "13" = "plutonic", "14" = "evaporite", "15" = "no_data",
  "16" = "water_ice"
)
lithology_groups <- c(
  "unconsolidated", "siliciclastic", "mixed_sedimentary", "carbonate",
  "metamorphic", "plutonic", "volcanic", "evaporite"
)
all_groups <- c(lithology_groups, "water_ice", "no_data")

build_region <- function(region) {
  message("GLiM region: ", region)
  basins <- river_sr_read_l6_basins(context, region)
  region_ids <- scope[basin_region == region, hybas_id]
  basin_keys <- sprintf("%.0f", as.numeric(basins$HYBAS_ID))
  basins <- basins[basin_keys %in% region_ids, , drop = FALSE]
  river_sr_assert(nrow(basins) > 0L, paste("No in-scope HydroBASINS found for region", region))
  required <- c("HYBAS_ID", "NEXT_DOWN", "SUB_AREA", "UP_AREA")
  river_sr_assert(all(required %in% names(basins)), paste("HydroBASINS fields missing in region", region))
  basins$basin_row_id <- seq_len(nrow(basins))
  attributes <- data.table::as.data.table(sf::st_drop_geometry(basins))[, ..required]
  attributes[, basin_row_id := seq_len(.N)]

  extracted <- data.table::as.data.table(terra::extract(
    glim_stack,
    terra::makeValid(terra::vect(basins)),
    exact = TRUE,
    cells = TRUE,
    ID = TRUE
  ))
  coverage_column <- intersect(c("fraction", "weight"), names(extracted))
  river_sr_assert(length(coverage_column) == 1L, "GLiM extraction did not return an exact coverage fraction.")
  extracted <- extracted[
    !is.na(glim_class) & is.finite(cell_area_km2) & is.finite(get(coverage_column))
  ]
  extracted[, `:=`(
    glim_class = as.integer(round(glim_class)),
    lithology_group = unname(class_group[as.character(as.integer(round(glim_class)))]),
    covered_area_km2 = cell_area_km2 * get(coverage_column)
  )]
  river_sr_assert(!anyNA(extracted$lithology_group), "GLiM contains an unmapped class code.")

  local <- extracted[, .(covered_area_km2 = sum(covered_area_km2)), by = .(ID, lithology_group)]
  local <- data.table::dcast(
    local,
    ID ~ lithology_group,
    value.var = "covered_area_km2",
    fill = 0
  )
  data.table::setnames(local, setdiff(names(local), "ID"), paste0("local_area_", setdiff(names(local), "ID")))
  table <- merge(attributes, local, by.x = "basin_row_id", by.y = "ID", all.x = TRUE, sort = FALSE)

  local_area_columns <- paste0("local_area_", all_groups)
  for (column in local_area_columns) {
    if (!column %in% names(table)) table[, (column) := 0]
    data.table::set(table, which(is.na(table[[column]])), column, 0)
  }
  local_lith_columns <- paste0("local_area_", lithology_groups)
  table[, local_lith_area_km2 := rowSums(.SD), .SDcols = local_lith_columns]
  for (group in lithology_groups) {
    table[, (paste0("local_geo_", group, "_frac")) := ifelse(
      local_lith_area_km2 > 0,
      get(paste0("local_area_", group)) / local_lith_area_km2,
      NA_real_
    )]
  }

  accumulated <- river_sr_accumulate_downstream(table, local_area_columns)
  upstream_area_columns <- paste0("up_area_", all_groups)
  for (i in seq_along(upstream_area_columns)) {
    table[, (upstream_area_columns[[i]]) := accumulated[, i]]
  }
  upstream_lith_columns <- paste0("up_area_", lithology_groups)
  table[, up_lith_area_km2 := rowSums(.SD), .SDcols = upstream_lith_columns]
  for (group in lithology_groups) {
    table[, (paste0("up_geo_", group, "_frac")) := ifelse(
      up_lith_area_km2 > 0,
      get(paste0("up_area_", group)) / up_lith_area_km2,
      NA_real_
    )]
  }

  keep <- c(
    "HYBAS_ID",
    paste0("local_geo_", lithology_groups, "_frac"),
    paste0("up_geo_", lithology_groups, "_frac")
  )
  table[, ..keep]
}

basin_geology <- data.table::rbindlist(
  lapply(river_sr_region_codes(), build_region),
  use.names = TRUE
)
basin_geology[, hybas_id := sprintf("%.0f", as.numeric(HYBAS_ID))]
river_sr_assert(!anyDuplicated(basin_geology$hybas_id), "GLiM basin table has duplicated HYBAS_ID values.")

assignment <- data.table::as.data.table(readRDS(assignment_path))
up_index <- match(assignment$current_hybas_id, basin_geology$hybas_id)
local_index <- match(assignment$hybrid_hybas_id, basin_geology$hybas_id)

result <- assignment[, .(
  site_id,
  r47__current_hybas_id = current_hybas_id,
  r47__legacy_hybas_id = legacy_hybas_id,
  r47__hybrid_hybas_id = hybrid_hybas_id,
  r47__hybas_source = hybas_source
)]
for (group in lithology_groups) {
  result[, (paste0("p0__up_geo_", group, "_frac")) :=
    basin_geology[[paste0("up_geo_", group, "_frac")]][up_index]]
  result[, (paste0("r47__local_geo_", group)) :=
    basin_geology[[paste0("local_geo_", group, "_frac")]][local_index]]
}

data.table::setorder(result, site_id)
river_sr_save_rds(result, output_path)
message(sprintf(
  "04 complete: GLiM local and upstream lithology built for %d sites: %s",
  nrow(result), output_path
))
