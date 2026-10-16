regional_v2_add_process14 <- function(validated, context) {
  dat <- validated$v1

  dat$metamorphic_contrast <- as.numeric(dat$r47__local_minus_up_geo_metamorphic)
  dat$age_mean_contrast_ma <- as.numeric(dat$local_geo_age_mean_ma) - as.numeric(dat$up_geo_age_mean_ma)
  dat$log_specific_discharge_proxy <- as.numeric(dat$p0__log_DIS_AV_CMS) - as.numeric(dat$p0__log_UPLAND_SKM)
  dat$age_max_contrast_ma <- as.numeric(dat$local_geo_age_max_oldest_ma) - as.numeric(dat$up_geo_age_max_oldest_ma)
  dat$old2000_contrast <- as.numeric(dat$local_geo_frac_midpoint_gt_2000) - as.numeric(dat$up_geo_frac_midpoint_gt_2000)
  dat$old1000_contrast <- as.numeric(dat$local_geo_frac_midpoint_gt_1000) - as.numeric(dat$up_geo_frac_midpoint_gt_1000)
  dat$upstream_radiogenic_lithology_frac <- as.numeric(dat$r50__upstream_radiogenic_crystalline)
  dat$age_sd_contrast_ma <- as.numeric(dat$local_geo_age_sd_ma) - as.numeric(dat$up_geo_age_sd_ma)
  dat$log_upstream_to_local_area_proxy <- as.numeric(dat$p0__log_UPLAND_SKM) - as.numeric(dat$p0__log_CATCH_SKM)
  dat$plutonic_contrast <- as.numeric(dat$r47__local_minus_up_geo_plutonic)
  dat$carbonate_contrast <- as.numeric(dat$r47__local_minus_up_geo_carbonate)

  distance_up <- expm1(as.numeric(dat$p0__log_DIST_UP_KM))
  distance_down <- expm1(as.numeric(dat$p0__log_DIST_DN_KM))
  distance_total <- distance_up + distance_down
  regional_v2_assert(all(is.finite(distance_total) & distance_total > 0), "Relative downstream position has a non-positive denominator.")
  dat$relative_downstream_position <- distance_up / distance_total

  dat$old_crust_tail_proxy <- as.numeric(dat$r50__upstream_radiogenic_crystalline) *
    as.numeric(dat$up_geo_frac_midpoint_gt_2000)
  dat$old_crust_source_proxy <- as.numeric(dat$r50__upstream_radiogenic_crystalline) *
    (as.numeric(dat$up_geo_age_mean_ma) / 1000)

  expected_order <- c(names(validated$v1), validated$process14)
  regional_v2_assert(identical(names(dat), expected_order), "Process14 fields were not appended in frozen manifest order.")
  dat
}
