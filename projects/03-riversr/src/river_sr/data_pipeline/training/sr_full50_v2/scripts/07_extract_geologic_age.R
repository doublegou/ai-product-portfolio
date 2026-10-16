file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

assignment_path <- river_sr_path(context, context$config$output$basin_assignment)
scope_path <- river_sr_path(context, context$config$output$basin_scope)
output_path <- river_sr_path(context, context$config$output$geologic_age)
nrcan_root <- river_sr_path(context, "data/raw/features/geology/nrcan_of5529/of_5529")
shapefile <- file.path(nrcan_root, "data/ArcMap9_ArcReader9/AllThemesMerged/roxworld.shp")
dbf_root <- file.path(nrcan_root, "data/DBase_Files/rudbf")
dbf_paths <- file.path(dbf_root, c("rudt.dbf", "ruagedt.dbf", "agetsmlt.dbf"))
river_sr_assert(file.exists(assignment_path), paste("Run step 02 first; missing:", assignment_path))
river_sr_assert(file.exists(scope_path), paste("Run step 02 first; missing:", scope_path))
river_sr_assert(file.exists(shapefile) && all(file.exists(dbf_paths)), "NRCan OF5529 age inputs are incomplete.")

suppressPackageStartupMessages({
  library(sf)
  library(data.table)
})
sf::sf_use_s2(FALSE)
clean_text <- function(x) trimws(iconv(as.character(x), from = "latin1", to = "UTF-8", sub = ""))
normalise_text <- function(x) toupper(gsub("[^A-Z0-9]+", " ", clean_text(x)))
read_dbf <- function(path) data.table::as.data.table(foreign::read.dbf(path, as.is = TRUE))

rudt <- read_dbf(dbf_paths[[1L]])
ages <- read_dbf(dbf_paths[[2L]])
lookup <- read_dbf(dbf_paths[[3L]])
for (column in c("RUNO", "ID2", "RUNO_ID2")) {
  rudt[, (column) := as.numeric(get(column))]
  ages[, (column) := as.numeric(get(column))]
}
lookup[, `:=`(
  AGEDESCAT = clean_text(AGEDESCAT),
  text_key = paste(normalise_text(AGEDES), normalise_text(AGEQU)),
  STARTMA = as.numeric(STARTMA),
  ENDMA = as.numeric(ENDMA)
)]
lookup <- lookup[!duplicated(AGEDESCAT)]
start_lookup <- lookup[, .(STARTCAT = AGEDESCAT, oldest_by_category = STARTMA)]
end_lookup <- lookup[, .(ENDCAT = AGEDESCAT, youngest_by_category = ENDMA)]
start_text_lookup <- lookup[!duplicated(text_key), .(start_text_key = text_key, oldest_by_text = STARTMA)]
end_text_lookup <- lookup[!duplicated(text_key), .(end_text_key = text_key, youngest_by_text = ENDMA)]

entity <- merge(rudt, ages, by = c("RUNO", "ID2", "RUNO_ID2"), all = TRUE, sort = FALSE)
entity[, `:=`(
  STARTCAT = clean_text(STARTCAT), ENDCAT = clean_text(ENDCAT),
  start_text_key = paste(normalise_text(STARTAGE), normalise_text(STARTQU)),
  end_text_key = paste(normalise_text(ENDAGE), normalise_text(ENDQU)),
  DEFLT = toupper(clean_text(DEFLT)), PERCENPLY = as.numeric(PERCENPLY)
)]
entity <- merge(entity, start_lookup, by = "STARTCAT", all.x = TRUE, sort = FALSE)
entity <- merge(entity, end_lookup, by = "ENDCAT", all.x = TRUE, sort = FALSE)
entity <- merge(entity, start_text_lookup, by = "start_text_key", all.x = TRUE, sort = FALSE)
entity <- merge(entity, end_text_lookup, by = "end_text_key", all.x = TRUE, sort = FALSE)
entity[, `:=`(
  oldest_ma = ifelse(is.finite(oldest_by_category), oldest_by_category, oldest_by_text),
  youngest_ma = ifelse(is.finite(youngest_by_category), youngest_by_category, youngest_by_text)
)]
# One documented source typo in OF5529: RUNO 9403, JURRASSIC -> JURASSIC.
jurassic_middle <- lookup[normalise_text(AGEDES) == "JURASSIC" & normalise_text(AGEQU) == "MIDDLE"]
if (nrow(jurassic_middle) == 1L) {
  entity[RUNO == 9403 & normalise_text(STARTAGE) == "JURRASSIC" & normalise_text(STARTQU) == "MIDDLE",
         oldest_ma := jurassic_middle$STARTMA[[1L]]]
}
entity[, `:=`(
  complete = is.finite(oldest_ma) & is.finite(youngest_ma) & oldest_ma >= youngest_ma,
  is_default = DEFLT == "Y",
  midpoint_ma = (oldest_ma + youngest_ma) / 2
)]

resolve_runo <- function(x) {
  default <- x[is_default == TRUE & complete == TRUE]
  candidates <- default
  if (nrow(candidates) == 0L) candidates <- x[complete == TRUE]
  if (nrow(candidates) == 0L) return(NULL)
  if (nrow(default) > 1L && nrow(unique(default[, .(oldest_ma, youngest_ma)])) > 1L) {
    weighted <- default[is.finite(PERCENPLY) & PERCENPLY > 0]
    if (nrow(weighted) == nrow(default) && sum(weighted$PERCENPLY) >= 99 && sum(weighted$PERCENPLY) <= 101) {
      candidates <- weighted
      weights <- candidates$PERCENPLY / sum(candidates$PERCENPLY)
    } else if (nrow(default[complete == TRUE]) == 1L) {
      candidates <- default[complete == TRUE]
      weights <- 1
    } else {
      return(NULL)
    }
  } else {
    candidates <- candidates[1L]
    weights <- 1
  }
  mean_age <- sum(weights * candidates$midpoint_ma)
  data.table::data.table(
    age_mean_ma = mean_age,
    age_sd_ma = sqrt(sum(weights * (candidates$midpoint_ma - mean_age)^2)),
    age_max_oldest_ma = max(candidates$oldest_ma),
    age_frac_midpoint_gt_1000 = sum(weights * (candidates$midpoint_ma > 1000)),
    age_frac_midpoint_gt_2000 = sum(weights * (candidates$midpoint_ma > 2000))
  )
}
runo_age <- entity[, resolve_runo(.SD), by = RUNO]
river_sr_assert(!anyDuplicated(runo_age$RUNO), "NRCan age crosswalk contains duplicate RUNO values.")

message("Reading and resolving NRCan global rock-unit polygons.")
rock <- sf::st_read(shapefile, quiet = TRUE)
rock$RUNO <- as.numeric(rock$RUNO)
rock <- merge(rock, runo_age, by = "RUNO", all.x = TRUE, sort = FALSE)
rock <- rock[is.finite(rock$age_mean_ma), , drop = FALSE]
rock <- suppressWarnings(sf::st_make_valid(sf::st_transform(rock, 6933)))
scope <- data.table::as.data.table(readRDS(scope_path))

summarise_region <- function(region) {
  message("Geologic age region: ", region)
  basins <- river_sr_read_l6_basins(context, region)
  region_ids <- scope[basin_region == region, hybas_id]
  basin_keys <- sprintf("%.0f", as.numeric(basins$HYBAS_ID))
  basins <- basins[basin_keys %in% region_ids, , drop = FALSE]
  river_sr_assert(nrow(basins) > 0L, paste("No in-scope HydroBASINS found for region", region))
  basins <- suppressWarnings(sf::st_make_valid(sf::st_transform(basins, 6933)))
  basin_box <- sf::st_as_sfc(sf::st_bbox(basins))
  rock_index <- lengths(sf::st_intersects(rock, basin_box)) > 0L
  regional_rock <- rock[rock_index, c(
    "age_mean_ma", "age_sd_ma", "age_max_oldest_ma",
    "age_frac_midpoint_gt_1000", "age_frac_midpoint_gt_2000"
  )]
  overlay <- suppressWarnings(sf::st_intersection(
    basins[, c("HYBAS_ID", "NEXT_DOWN")], regional_rock
  ))
  values <- data.table::as.data.table(sf::st_drop_geometry(overlay))
  values[, area_km2 := as.numeric(sf::st_area(overlay)) / 1e6]
  values <- values[is.finite(area_km2) & area_km2 > 0]
  local <- values[, .(
    valid_area_km2 = sum(area_km2),
    age_mean_num = sum(area_km2 * age_mean_ma),
    age_second_num = sum(area_km2 * (age_sd_ma^2 + age_mean_ma^2)),
    gt1000_num = sum(area_km2 * age_frac_midpoint_gt_1000),
    gt2000_num = sum(area_km2 * age_frac_midpoint_gt_2000),
    local_geo_age_max_oldest_ma = max(age_max_oldest_ma)
  ), by = HYBAS_ID]
  attributes <- data.table::as.data.table(sf::st_drop_geometry(basins))[, .(HYBAS_ID, NEXT_DOWN)]
  attributes[, basin_area_km2 := as.numeric(sf::st_area(basins)) / 1e6]
  table <- merge(attributes, local, by = "HYBAS_ID", all.x = TRUE, sort = FALSE)
  sum_columns <- c("basin_area_km2", "valid_area_km2", "age_mean_num", "age_second_num", "gt1000_num", "gt2000_num")
  for (column in setdiff(sum_columns, "basin_area_km2")) data.table::set(table, which(is.na(table[[column]])), column, 0)
  upstream <- river_sr_accumulate_downstream(table, sum_columns)
  colnames(upstream) <- sum_columns
  local_mean <- ifelse(table$valid_area_km2 > 0, table$age_mean_num / table$valid_area_km2, NA_real_)
  local_sd <- sqrt(pmax(0, ifelse(table$valid_area_km2 > 0, table$age_second_num / table$valid_area_km2 - local_mean^2, NA_real_)))
  up_mean <- ifelse(upstream[, "valid_area_km2"] > 0, upstream[, "age_mean_num"] / upstream[, "valid_area_km2"], NA_real_)
  up_sd <- sqrt(pmax(0, ifelse(upstream[, "valid_area_km2"] > 0, upstream[, "age_second_num"] / upstream[, "valid_area_km2"] - up_mean^2, NA_real_)))
  data.table::data.table(
    HYBAS_ID = table$HYBAS_ID,
    local_geo_age_max_oldest_ma = table$local_geo_age_max_oldest_ma,
    local_geo_age_mean_ma = local_mean,
    local_geo_age_sd_ma = local_sd,
    local_geo_frac_midpoint_gt_1000 = ifelse(table$valid_area_km2 > 0, table$gt1000_num / table$valid_area_km2, NA_real_),
    local_geo_frac_midpoint_gt_2000 = ifelse(table$valid_area_km2 > 0, table$gt2000_num / table$valid_area_km2, NA_real_),
    up_geo_age_max_oldest_ma = river_sr_accumulate_downstream_max(table, "local_geo_age_max_oldest_ma"),
    up_geo_age_mean_ma = up_mean,
    up_geo_age_sd_ma = up_sd,
    up_geo_frac_midpoint_gt_1000 = ifelse(upstream[, "valid_area_km2"] > 0, upstream[, "gt1000_num"] / upstream[, "valid_area_km2"], NA_real_),
    up_geo_frac_midpoint_gt_2000 = ifelse(upstream[, "valid_area_km2"] > 0, upstream[, "gt2000_num"] / upstream[, "valid_area_km2"], NA_real_),
    local_geo_age_resolved_coverage = ifelse(table$basin_area_km2 > 0, table$valid_area_km2 / table$basin_area_km2, NA_real_),
    up_geo_age_resolved_coverage = ifelse(upstream[, "basin_area_km2"] > 0, upstream[, "valid_area_km2"] / upstream[, "basin_area_km2"], NA_real_)
  )
}

basin_age <- data.table::rbindlist(lapply(river_sr_region_codes(), summarise_region), use.names = TRUE)
basin_age[, hybas_id := sprintf("%.0f", as.numeric(HYBAS_ID))]
assignment <- data.table::as.data.table(readRDS(assignment_path))
index <- match(assignment$current_hybas_id, basin_age$hybas_id)
result <- data.table::data.table(site_id = assignment$site_id)
age_columns <- setdiff(names(basin_age), c("HYBAS_ID", "hybas_id"))
for (column in age_columns) result[, (column) := basin_age[[column]][index]]
data.table::setorder(result, site_id)
river_sr_save_rds(result, output_path)
message(sprintf("07 complete: NRCan geologic-age predictors built for %d sites: %s", nrow(result), output_path))
