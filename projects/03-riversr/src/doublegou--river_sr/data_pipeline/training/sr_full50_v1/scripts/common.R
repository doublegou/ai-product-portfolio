river_sr_assert <- function(condition, message) {
  if (!isTRUE(condition)) {
    stop(message, call. = FALSE)
  }
}

river_sr_context <- function(script_path) {
  project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
  repo_root <- project_dir
  repeat {
    if (file.exists(file.path(repo_root, "env", "activate.R"))) {
      break
    }
    parent <- dirname(repo_root)
    river_sr_assert(
      !identical(parent, repo_root),
      "Cannot find the RiverSR repository root."
    )
    repo_root <- parent
  }
  repo_root <- normalizePath(repo_root, mustWork = TRUE)

  source(file.path(repo_root, "env", "activate.R"), local = TRUE)
  river_sr_activate(repo_root)

  list(
    repo_root = repo_root,
    project_dir = project_dir,
    config = yaml::read_yaml(file.path(project_dir, "config", "default.yml"))
  )
}

river_sr_path <- function(context, relative_path) {
  file.path(context$repo_root, relative_path)
}

river_sr_site_id <- function(latitude, longitude, digits = 5L) {
  key <- paste(round(latitude, digits), round(longitude, digits), sep = "_")
  vapply(
    key,
    digest::digest,
    character(1L),
    algo = "xxhash64",
    serialize = FALSE,
    USE.NAMES = FALSE
  )
}

river_sr_reference_id <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_|_$", "", x)
}

river_sr_save_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary_path <- tempfile(pattern = "river_sr_", tmpdir = dirname(path))
  on.exit(unlink(temporary_path), add = TRUE)
  saveRDS(object, temporary_path, version = 3L)
  if (file.exists(path)) {
    unlink(path)
  }
  river_sr_assert(file.rename(temporary_path, path), paste("Could not write:", path))
}

river_sr_write_csv <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary_path <- tempfile(pattern = "river_sr_", tmpdir = dirname(path))
  on.exit(unlink(temporary_path), add = TRUE)
  data.table::fwrite(object, temporary_path, na = "")
  if (file.exists(path)) {
    unlink(path)
  }
  river_sr_assert(file.rename(temporary_path, path), paste("Could not write:", path))
}

river_sr_write_json <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary_path <- tempfile(pattern = "river_sr_", tmpdir = dirname(path))
  on.exit(unlink(temporary_path), add = TRUE)
  jsonlite::write_json(object, temporary_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
  if (file.exists(path)) unlink(path)
  river_sr_assert(file.rename(temporary_path, path), paste("Could not write:", path))
}

river_sr_sha256 <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

river_sr_file_record <- function(path, repo_root) {
  absolute <- normalizePath(path, mustWork = TRUE)
  list(
    path = gsub("\\\\", "/", substring(absolute, nchar(normalizePath(repo_root, mustWork = TRUE)) + 2L)),
    bytes = unname(file.info(absolute)$size),
    sha256 = river_sr_sha256(absolute)
  )
}

river_sr_region_codes <- function() {
  c("af", "ar", "as", "au", "eu", "gr", "na", "sa", "si")
}

river_sr_read_l6_basins <- function(context, region) {
  path <- river_sr_path(
    context,
    file.path(
      "data/raw/features/hydrography/hydrobasins_l6",
      region,
      paste0("hybas_", region, "_lev06_v1c.shp")
    )
  )
  river_sr_assert(file.exists(path), paste("Missing HydroBASINS file:", path))
  x <- sf::st_read(path, quiet = TRUE)
  if (sf::st_crs(x)$epsg != 4326L) {
    x <- sf::st_transform(x, 4326)
  }
  x <- suppressWarnings(sf::st_wrap_dateline(
    x,
    options = c("WRAPDATELINE=YES", "DATELINEOFFSET=10"),
    quiet = TRUE
  ))
  x <- sf::st_make_valid(x)
  x <- suppressWarnings(sf::st_collection_extract(x, "POLYGON"))
  x <- suppressWarnings(sf::st_cast(x, "MULTIPOLYGON"))
  x <- x[!sf::st_is_empty(x), , drop = FALSE]
  x$basin_region <- region
  x
}

river_sr_accumulate_downstream <- function(table, value_columns) {
  ids <- sprintf("%.0f", as.numeric(table$HYBAS_ID))
  next_ids <- ifelse(
    is.na(table$NEXT_DOWN) | table$NEXT_DOWN == 0,
    NA_character_,
    sprintf("%.0f", as.numeric(table$NEXT_DOWN))
  )
  lookup <- setNames(seq_len(nrow(table)), ids)
  downstream <- unname(lookup[next_ids])
  indegree <- tabulate(downstream[!is.na(downstream)], nbins = nrow(table))
  queue <- which(indegree == 0L)
  position <- 1L
  values <- as.matrix(as.data.frame(table)[, value_columns, drop = FALSE])
  storage.mode(values) <- "double"
  processed <- logical(nrow(table))

  while (position <= length(queue)) {
    current <- queue[[position]]
    position <- position + 1L
    processed[[current]] <- TRUE
    target <- downstream[[current]]
    if (!is.na(target)) {
      values[target, ] <- values[target, ] + values[current, ]
      indegree[[target]] <- indegree[[target]] - 1L
      if (indegree[[target]] == 0L) {
        queue <- c(queue, target)
      }
    }
  }
  river_sr_assert(all(processed), "HydroBASINS downstream accumulation found a cycle.")
  values
}

river_sr_upstream_scope <- function(network, target_ids) {
  ids <- sprintf("%.0f", as.numeric(network$HYBAS_ID))
  downstream <- ifelse(
    is.na(network$NEXT_DOWN) | network$NEXT_DOWN == 0,
    NA_character_,
    sprintf("%.0f", as.numeric(network$NEXT_DOWN))
  )
  needed <- unique(as.character(target_ids[!is.na(target_ids)]))
  repeat {
    upstream <- ids[downstream %in% needed]
    expanded <- union(needed, upstream)
    if (length(expanded) == length(needed)) break
    needed <- expanded
  }
  needed
}

river_sr_accumulate_downstream_max <- function(table, value_column) {
  ids <- sprintf("%.0f", as.numeric(table$HYBAS_ID))
  next_ids <- ifelse(
    is.na(table$NEXT_DOWN) | table$NEXT_DOWN == 0,
    NA_character_,
    sprintf("%.0f", as.numeric(table$NEXT_DOWN))
  )
  lookup <- setNames(seq_len(nrow(table)), ids)
  downstream <- unname(lookup[next_ids])
  indegree <- tabulate(downstream[!is.na(downstream)], nbins = nrow(table))
  queue <- which(indegree == 0L)
  position <- 1L
  values <- as.numeric(table[[value_column]])
  processed <- logical(nrow(table))

  while (position <= length(queue)) {
    current <- queue[[position]]
    position <- position + 1L
    processed[[current]] <- TRUE
    target <- downstream[[current]]
    if (!is.na(target)) {
      candidates <- c(values[[target]], values[[current]])
      values[[target]] <- if (any(is.finite(candidates))) max(candidates, na.rm = TRUE) else NA_real_
      indegree[[target]] <- indegree[[target]] - 1L
      if (indegree[[target]] == 0L) queue <- c(queue, target)
    }
  }
  river_sr_assert(all(processed), "HydroBASINS downstream maximum found a cycle.")
  values
}

river_sr_summarise_rasters_by_l6 <- function(context, region, raster_stack, variable_names, basin_ids = NULL, chunk_size = 100L) {
  basins <- river_sr_read_l6_basins(context, region)
  if (!is.null(basin_ids)) {
    keys <- sprintf("%.0f", as.numeric(basins$HYBAS_ID))
    basins <- basins[keys %in% as.character(basin_ids), , drop = FALSE]
  }
  river_sr_assert(nrow(basins) > 0L, paste("No in-scope HydroBASINS found for region", region))
  river_sr_assert(
    all(c("HYBAS_ID", "NEXT_DOWN") %in% names(basins)),
    paste("HydroBASINS network fields are missing in region", region)
  )
  basin_vector <- terra::makeValid(terra::vect(basins))
  if (!terra::same.crs(basin_vector, raster_stack)) {
    basin_vector <- terra::project(basin_vector, terra::crs(raster_stack))
  }
  chunks <- split(seq_len(nrow(basins)), ceiling(seq_len(nrow(basins)) / chunk_size))

  summarise_chunk <- function(indices) {
    extracted <- data.table::as.data.table(terra::extract(
      raster_stack,
      basin_vector[indices],
      exact = TRUE,
      cells = TRUE,
      ID = TRUE
    ))
    base <- data.table::data.table(ID = seq_along(indices), basin_row_id = indices)
    if (nrow(extracted) == 0L) {
      base[, local_total_area_km2 := 0]
      for (variable in variable_names) {
        base[, (paste0(variable, "__numerator")) := 0]
        base[, (paste0(variable, "__valid_area")) := 0]
      }
      return(base)
    }
    coverage_column <- intersect(c("fraction", "weight"), names(extracted))
    river_sr_assert(length(coverage_column) == 1L, "Raster extraction did not return an exact coverage fraction.")
    extracted[, overlap_area_km2 := cell_area_km2 * get(coverage_column)]
    total <- extracted[
      is.finite(overlap_area_km2) & overlap_area_km2 > 0,
      .(local_total_area_km2 = sum(overlap_area_km2)),
      by = ID
    ]
    base <- merge(base, total, by = "ID", all.x = TRUE, sort = FALSE)
    base[is.na(local_total_area_km2), local_total_area_km2 := 0]
    for (variable in variable_names) {
      values <- extracted[
        is.finite(get(variable)) & is.finite(overlap_area_km2) & overlap_area_km2 > 0,
        .(
          numerator = sum(get(variable) * overlap_area_km2),
          valid_area = sum(overlap_area_km2)
        ),
        by = ID
      ]
      data.table::setnames(
        values,
        c("numerator", "valid_area"),
        c(paste0(variable, "__numerator"), paste0(variable, "__valid_area"))
      )
      base <- merge(base, values, by = "ID", all.x = TRUE, sort = FALSE)
      numerator_column <- paste0(variable, "__numerator")
      valid_area_column <- paste0(variable, "__valid_area")
      data.table::set(base, which(is.na(base[[numerator_column]])), numerator_column, 0)
      data.table::set(base, which(is.na(base[[valid_area_column]])), valid_area_column, 0)
    }
    base
  }

  local <- data.table::rbindlist(lapply(chunks, summarise_chunk), use.names = TRUE)
  attributes <- data.table::as.data.table(sf::st_drop_geometry(basins))[, .(HYBAS_ID, NEXT_DOWN)]
  attributes[, basin_row_id := seq_len(.N)]
  table <- merge(attributes, local, by = "basin_row_id", all.x = TRUE, sort = FALSE)
  data.table::setorder(table, basin_row_id)
  accumulation_columns <- c(
    "local_total_area_km2",
    as.vector(rbind(paste0(variable_names, "__numerator"), paste0(variable_names, "__valid_area")))
  )
  upstream <- river_sr_accumulate_downstream(table, accumulation_columns)
  colnames(upstream) <- accumulation_columns
  for (variable in variable_names) {
    numerator <- paste0(variable, "__numerator")
    valid_area <- paste0(variable, "__valid_area")
    table[, (paste0("local_", variable)) := ifelse(
      get(valid_area) > 0,
      get(numerator) / get(valid_area),
      NA_real_
    )]
    table[, (paste0("up_", variable)) := ifelse(
      upstream[, valid_area] > 0,
      upstream[, numerator] / upstream[, valid_area],
      NA_real_
    )]
  }
  keep <- c("HYBAS_ID", paste0("local_", variable_names), paste0("up_", variable_names))
  table[, ..keep]
}
