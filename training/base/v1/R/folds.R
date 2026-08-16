v1_assign_units_balanced <- function(units, k, seed) {
  v1_assert(is.data.frame(units) && all(c("validation_unit", "n_rows") %in% names(units)), "units must contain validation_unit and n_rows.")
  k <- as.integer(k)
  v1_assert(nrow(units) >= k && k >= 2L, "Not enough validation units for requested folds.")
  v1_assert(all(is.finite(units$n_rows)) && all(units$n_rows > 0), "n_rows must contain finite positive values.")
  set.seed(as.integer(seed))
  work <- units
  work$.original_order <- seq_len(nrow(work))
  work$.random_tie_breaker <- stats::runif(nrow(work))
  work <- work[order(-work$n_rows, work$.random_tie_breaker), , drop = FALSE]
  fold_rows <- rep(0, k)
  fold_units <- rep(0L, k)
  assigned <- integer(nrow(work))
  for (i in seq_len(nrow(work))) {
    if (i <= k) {
      chosen <- i
    } else {
      candidates <- which(fold_rows == min(fold_rows))
      if (length(candidates) > 1L) candidates <- candidates[fold_units[candidates] == min(fold_units[candidates])]
      chosen <- if (length(candidates) == 1L) candidates[[1L]] else sample(candidates, 1L)
    }
    assigned[[i]] <- chosen
    fold_rows[[chosen]] <- fold_rows[[chosen]] + work$n_rows[[i]]
    fold_units[[chosen]] <- fold_units[[chosen]] + 1L
  }
  work$fold <- assigned
  work <- work[order(work$.original_order), , drop = FALSE]
  work$.original_order <- NULL
  work$.random_tie_breaker <- NULL
  rownames(work) <- NULL
  work
}

v1_load_hydrobasins_attributes <- function(context) {
  v1_require_packages("sf")
  root <- v1_path(context, context$config$input$hydrobasins_root)
  files <- Sys.glob(file.path(root, "*", "hybas_*_lev06_v1c.shp"))
  v1_assert(length(files) == 9L, paste("Expected 9 regional HydroBASINS L6 shapefiles; found", length(files)))
  parts <- lapply(files, function(path) {
    x <- sf::st_read(path, quiet = TRUE)
    required <- c("HYBAS_ID", "NEXT_DOWN", "MAIN_BAS")
    v1_assert(all(required %in% names(x)), paste("HydroBASINS attributes are incomplete:", path))
    x <- sf::st_drop_geometry(x)[required]
    data.frame(
      current_hybas_id = sprintf("%.0f", x$HYBAS_ID),
      next_down = sprintf("%.0f", x$NEXT_DOWN),
      main_bas = sprintf("%.0f", x$MAIN_BAS),
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, parts)
  v1_assert(!anyDuplicated(result$current_hybas_id), "Combined HydroBASINS L6 contains duplicate HYBAS_ID values.")
  result
}

v1_build_hydrological_groups <- function(dat, context) {
  columns <- context$config$columns
  attributes <- v1_load_hydrobasins_attributes(context)
  rows <- data.frame(
    row_id = as.character(dat[[columns$row_id]]),
    site_id = as.character(dat[[columns$site_id]]),
    current_hybas_id = as.character(dat[[columns$current_hybas_id]]),
    stringsAsFactors = FALSE
  )
  mapped <- merge(rows, attributes, by = "current_hybas_id", all.x = TRUE, sort = FALSE)
  mapped <- mapped[match(rows$row_id, mapped$row_id), , drop = FALSE]
  v1_assert(identical(mapped$row_id, rows$row_id), "Hydrological mapping changed row order or identity.")
  v1_assert(!anyNA(mapped$main_bas) && all(nzchar(mapped$main_bas)), "One or more Full50 rows did not map to MAIN_BAS.")
  mapped$hydrological_group <- mapped$main_bas
  expected <- as.integer(context$config$validation$expected_hydrological_groups)
  observed <- length(unique(mapped$hydrological_group))
  v1_assert(observed == expected, paste("Expected", expected, "MAIN_BAS hydrological systems; found", observed))
  mapped[c("row_id", "site_id", "current_hybas_id", "main_bas", "next_down", "hydrological_group")]
}

v1_build_primary_folds <- function(groups, context) {
  repeats <- as.integer(context$config$validation$repeats)
  outer_k <- as.integer(context$config$validation$outer_folds)
  inner_k <- as.integer(context$config$validation$inner_folds)
  outer_records <- list()
  inner_records <- list()
  index <- 0L
  for (repeat_id in seq_len(repeats)) {
    units <- stats::aggregate(row_id ~ hydrological_group, groups, length)
    names(units) <- c("validation_unit", "n_rows")
    assigned <- v1_assign_units_balanced(
      units, outer_k, as.integer(context$config$validation$hydrological_outer_seed_base) + repeat_id
    )
    outer <- merge(
      groups[c("row_id", "hydrological_group")], assigned[c("validation_unit", "fold")],
      by.x = "hydrological_group", by.y = "validation_unit", sort = FALSE
    )
    outer <- outer[match(groups$row_id, outer$row_id), , drop = FALSE]
    outer_records[[repeat_id]] <- data.frame(
      row_id = outer$row_id,
      scheme = "hydrological",
      repeat_id = repeat_id,
      outer_fold = outer$fold,
      validation_unit = outer$hydrological_group,
      stringsAsFactors = FALSE
    )
    for (outer_fold in seq_len(outer_k)) {
      training <- outer[outer$fold != outer_fold, , drop = FALSE]
      inner_units <- stats::aggregate(row_id ~ hydrological_group, training, length)
      names(inner_units) <- c("validation_unit", "n_rows")
      inner_assigned <- v1_assign_units_balanced(
        inner_units,
        inner_k,
        as.integer(context$config$validation$hydrological_inner_seed_base) + repeat_id * 100L + outer_fold
      )
      inner <- merge(
        training, inner_assigned[c("validation_unit", "fold")],
        by.x = "hydrological_group", by.y = "validation_unit", sort = FALSE
      )
      inner <- inner[match(training$row_id, inner$row_id), , drop = FALSE]
      index <- index + 1L
      inner_records[[index]] <- data.frame(
        row_id = inner$row_id,
        scheme = "hydrological",
        repeat_id = repeat_id,
        outer_fold = outer_fold,
        inner_fold = inner$fold.y,
        validation_unit = inner$hydrological_group,
        stringsAsFactors = FALSE
      )
    }
  }
  list(outer = do.call(rbind, outer_records), inner = do.call(rbind, inner_records))
}

v1_build_deployment_folds <- function(groups, context) {
  units <- stats::aggregate(row_id ~ hydrological_group, groups, length)
  names(units) <- c("validation_unit", "n_rows")
  assigned <- v1_assign_units_balanced(
    units,
    as.integer(context$config$validation$deployment_folds),
    as.integer(context$config$validation$deployment_seed)
  )
  result <- merge(
    groups[c("row_id", "hydrological_group")], assigned[c("validation_unit", "fold")],
    by.x = "hydrological_group", by.y = "validation_unit", sort = FALSE
  )
  result <- result[match(groups$row_id, result$row_id), , drop = FALSE]
  data.frame(
    row_id = result$row_id,
    deployment_fold = result$fold,
    validation_unit = result$hydrological_group,
    stringsAsFactors = FALSE
  )
}

v1_build_stress_folds <- function(dat, context) {
  columns <- context$config$columns
  row_id <- as.character(dat[[columns$row_id]])
  longitude <- dat[[columns$longitude]]
  latitude <- dat[[columns$latitude]]
  radius <- 6371008.8
  longitude_rad <- longitude * pi / 180
  latitude_rad <- latitude * pi / 180
  cv_x_m <- radius * longitude_rad * cos(latitude_rad)
  cv_y_m <- radius * latitude_rad
  outer_k <- as.integer(context$config$validation$outer_folds)
  records <- list()
  index <- 0L
  for (scale_km in as.integer(unlist(context$config$validation$spatial_scales_km))) {
    scheme <- paste0("spatial_", scale_km)
    unit <- paste(scheme, floor(cv_x_m / (scale_km * 1000)), floor(cv_y_m / (scale_km * 1000)), sep = "__")
    rows <- data.frame(row_id = row_id, scheme = scheme, validation_unit = unit, stringsAsFactors = FALSE)
    units <- stats::aggregate(row_id ~ validation_unit, rows, length)
    names(units)[[2L]] <- "n_rows"
    assigned <- v1_assign_units_balanced(
      units, outer_k, as.integer(context$config$validation$spatial_outer_seed_base) + scale_km
    )
    current <- merge(rows, assigned[c("validation_unit", "fold")], by = "validation_unit", sort = FALSE)
    current <- current[match(row_id, current$row_id), , drop = FALSE]
    index <- index + 1L
    records[[index]] <- data.frame(
      row_id = current$row_id, scheme = scheme, outer_fold = current$fold,
      validation_unit = current$validation_unit, stringsAsFactors = FALSE
    )
  }
  reference <- trimws(as.character(dat[[columns$reference]]))
  rows <- data.frame(row_id = row_id, scheme = "reference", validation_unit = reference, stringsAsFactors = FALSE)
  units <- stats::aggregate(row_id ~ validation_unit, rows, length)
  names(units)[[2L]] <- "n_rows"
  assigned <- v1_assign_units_balanced(units, outer_k, as.integer(context$config$validation$reference_outer_seed))
  current <- merge(rows, assigned[c("validation_unit", "fold")], by = "validation_unit", sort = FALSE)
  current <- current[match(row_id, current$row_id), , drop = FALSE]
  records[[length(records) + 1L]] <- data.frame(
    row_id = current$row_id, scheme = "reference", outer_fold = current$fold,
    validation_unit = current$validation_unit, stringsAsFactors = FALSE
  )
  do.call(rbind, records)
}
