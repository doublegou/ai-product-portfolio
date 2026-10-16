v0_assign_units_balanced <- function(units, k, seed) {
  v0_assert(is.data.frame(units) && "n_rows" %in% names(units), "units must contain n_rows.")
  k <- as.integer(k)
  v0_assert(nrow(units) >= k && k >= 2L, "Not enough validation units for requested folds.")
  v0_assert(all(is.finite(units$n_rows)) && all(units$n_rows > 0), "n_rows must contain finite positive values.")

  set.seed(seed)
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
      if (length(candidates) > 1L) {
        candidates <- candidates[fold_units[candidates] == min(fold_units[candidates])]
      }
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

v0_build_spatial_folds <- function(dat, context) {
  v0_require_packages("dplyr")
  columns <- context$config$columns
  row_id <- as.character(dat[[columns$row_id]])
  longitude <- dat[[columns$longitude]]
  latitude <- dat[[columns$latitude]]
  radius <- 6371008.8
  longitude_rad <- longitude * pi / 180
  latitude_rad <- latitude * pi / 180
  cv_x_m <- radius * longitude_rad * cos(latitude_rad)
  cv_y_m <- radius * latitude_rad
  scales <- as.integer(unlist(context$config$validation$spatial_scales_km))
  outer_k <- as.integer(context$config$validation$outer_folds)
  inner_k <- as.integer(context$config$validation$inner_folds)
  outer_records <- list()
  inner_records <- list()

  for (scale_km in scales) {
    scheme <- paste0("spatial_", scale_km)
    unit <- paste(scheme, floor(cv_x_m / (scale_km * 1000)), floor(cv_y_m / (scale_km * 1000)), sep = "__")
    rows <- data.frame(row_id = row_id, scheme = scheme, validation_unit = unit, stringsAsFactors = FALSE)
    units <- dplyr::count(rows, validation_unit, name = "n_rows")
    assigned <- v0_assign_units_balanced(
      units, outer_k, as.integer(context$config$validation$spatial_outer_seed_base) + scale_km
    )
    outer <- dplyr::left_join(rows, assigned[c("validation_unit", "fold")], by = "validation_unit")
    names(outer)[names(outer) == "fold"] <- "outer_fold"
    outer_records[[scheme]] <- outer

    for (outer_fold in seq_len(outer_k)) {
      training <- outer[outer$outer_fold != outer_fold, , drop = FALSE]
      inner_units <- dplyr::count(training, validation_unit, name = "n_rows")
      inner_assigned <- v0_assign_units_balanced(
        inner_units,
        inner_k,
        as.integer(context$config$validation$spatial_inner_seed_base) + scale_km * 10L + outer_fold
      )
      inner <- dplyr::left_join(training, inner_assigned[c("validation_unit", "fold")], by = "validation_unit")
      names(inner)[names(inner) == "fold"] <- "inner_fold"
      inner$outer_fold <- outer_fold
      inner_records[[paste(scheme, outer_fold, sep = "__")]] <- inner[c(
        "row_id", "scheme", "outer_fold", "inner_fold", "validation_unit"
      )]
    }
  }

  list(
    outer = dplyr::bind_rows(outer_records)[c("row_id", "scheme", "outer_fold", "validation_unit")],
    inner = dplyr::bind_rows(inner_records)
  )
}
