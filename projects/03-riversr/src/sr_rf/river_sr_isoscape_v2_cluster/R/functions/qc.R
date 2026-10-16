make_site_id <- function(latitude, longitude, digits = 5L) {
  key <- paste(round(latitude, digits), round(longitude, digits), sep = "_")
  vapply(key, digest::digest, character(1), algo = "xxhash64", serialize = FALSE)
}

add_qc_flags <- function(dat, cfg) {
  q <- cfg$qc
  required <- c("latitude","longitude","sr87_sr86","short_references")
  missing_required <- setdiff(required, names(dat))
  if (length(missing_required)) stop("Missing required columns: ", paste(missing_required, collapse=", "))

  dat <- dat |>
    dplyr::mutate(
      row_id = sprintf("obs_%06d", dplyr::row_number()),
      latitude = as.numeric(latitude),
      longitude = as.numeric(longitude),
      sr87_sr86 = as.numeric(sr87_sr86),
      sr87_sr86_uncertainty = as.numeric(sr87_sr86_uncertainty),
      sr_concentration_ppm = as.numeric(sr_concentration_ppm),
      sr_concentration_ppm_uncertainty = as.numeric(sr_concentration_ppm_uncertainty),
      flag_missing_core = is.na(latitude) | is.na(longitude) | is.na(sr87_sr86),
      flag_invalid_coordinate = !is.na(latitude) & !is.na(longitude) &
        (latitude < -90 | latitude > 90 | longitude < -180 | longitude > 180),
      flag_sr_outside_hard_bounds = !is.na(sr87_sr86) &
        (sr87_sr86 < q$hard_sr_min | sr87_sr86 > q$hard_sr_max),
      flag_uncertainty_nonpositive = !is.na(sr87_sr86_uncertainty) & sr87_sr86_uncertainty <= 0,
      flag_uncertainty_large = !is.na(sr87_sr86_uncertainty) & sr87_sr86_uncertainty > 0.005,
      flag_concentration_nonpositive = !is.na(sr_concentration_ppm) & sr_concentration_ppm <= 0,
      flag_concentration_unit_review = !is.na(sr_concentration_ppm) &
        sr_concentration_ppm > q$concentration_review_threshold_ppm,
      reference_id = safe_name(short_references),
      site_id = make_site_id(latitude, longitude, q$coordinate_round_digits),
      high_ge_0718 = sr87_sr86 >= 0.718,
      high_ge_0720 = sr87_sr86 >= 0.720,
      high_ge_0722 = sr87_sr86 >= 0.722
    )

  exact_key <- dat |>
    dplyr::transmute(
      key = paste(short_references, original_sample_id, latitude, longitude, sr87_sr86, sep = "|")
    ) |>
    dplyr::pull(key)

  dat$flag_exact_measurement_duplicate <- duplicated(exact_key) | duplicated(exact_key, fromLast = TRUE)
  dat$flag_sample_id_duplicate <- duplicated(dat$sample_id) | duplicated(dat$sample_id, fromLast = TRUE)
  dat$qc_keep_core <- !(dat$flag_missing_core | dat$flag_invalid_coordinate | dat$flag_sr_outside_hard_bounds)

  q90 <- stats::quantile(dat$sr87_sr86[dat$qc_keep_core], 0.90, na.rm = TRUE, names = FALSE)
  q95 <- stats::quantile(dat$sr87_sr86[dat$qc_keep_core], 0.95, na.rm = TRUE, names = FALSE)
  dat$observed_top10 <- dat$sr87_sr86 >= q90
  dat$observed_top05 <- dat$sr87_sr86 >= q95
  dat
}

make_qc_summary <- function(dat) {
  tibble::tibble(
    metric = c(
      "rows_total","rows_qc_keep_core","unique_sample_id","unique_site_id",
      "unique_reference_id","sr_min","sr_median","sr_max",
      "n_ge_0.718","n_ge_0.720","n_ge_0.722",
      "n_duplicate_sample_id","n_exact_measurement_duplicate",
      "concentration_nonmissing","concentration_unit_review"
    ),
    value = c(
      nrow(dat), sum(dat$qc_keep_core), dplyr::n_distinct(dat$sample_id),
      dplyr::n_distinct(dat$site_id), dplyr::n_distinct(dat$reference_id),
      min(dat$sr87_sr86, na.rm=TRUE), stats::median(dat$sr87_sr86, na.rm=TRUE),
      max(dat$sr87_sr86, na.rm=TRUE), sum(dat$high_ge_0718, na.rm=TRUE),
      sum(dat$high_ge_0720, na.rm=TRUE), sum(dat$high_ge_0722, na.rm=TRUE),
      sum(dat$flag_sample_id_duplicate, na.rm=TRUE),
      sum(dat$flag_exact_measurement_duplicate, na.rm=TRUE),
      sum(!is.na(dat$sr_concentration_ppm)),
      sum(dat$flag_concentration_unit_review, na.rm=TRUE)
    )
  )
}

tail_audit <- function(dat, threshold = 0.720) {
  dat |>
    dplyr::filter(qc_keep_core, sr87_sr86 >= threshold) |>
    dplyr::group_by(reference_id, short_references) |>
    dplyr::summarise(
      n_measurements = dplyr::n(),
      n_sites = dplyr::n_distinct(site_id),
      min_sr = min(sr87_sr86, na.rm=TRUE),
      median_sr = stats::median(sr87_sr86, na.rm=TRUE),
      max_sr = max(sr87_sr86, na.rm=TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(n_measurements), dplyr::desc(max_sr))
}
