fa_auc <- function(case, control) {
  comparisons <- outer(case, control, "-"); mean(comparisons > 0) + 0.5 * mean(comparisons == 0)
}

fa_overlap_audit <- function(validated, predictors, feature_set, context) {
  dat <- validated$data; missed <- dat[dat$.failure_role == "missed_high_sr", , drop = FALSE]; background <- dat[dat$.failure_role == "background", , drop = FALSE]
  q <- as.numeric(unlist(context$config$overlap_audit$background_quantiles)); strong_cut <- as.numeric(context$config$overlap_audit$strong_univariate_auc); overlap_cut <- as.numeric(context$config$overlap_audit$low_background_overlap_fraction)
  feature_rows <- lapply(predictors, function(feature) {
    bounds <- stats::quantile(background[[feature]], probs = q, names = FALSE, type = 8)
    inside <- missed[[feature]] >= bounds[1] & missed[[feature]] <= bounds[2]; raw_auc <- fa_auc(missed[[feature]], background[[feature]]); oriented <- max(raw_auc, 1 - raw_auc)
    data.frame(feature_set = feature_set, feature = feature, background_q05 = bounds[1], background_q95 = bounds[2], missed_in_background_interval_fraction = mean(inside),
      raw_auc = raw_auc, orientation_free_auc = oriented, strong_univariate_discrimination = oriented >= strong_cut, low_background_overlap = mean(inside) <= overlap_cut,
      strong_and_low_overlap = oriented >= strong_cut & mean(inside) <= overlap_cut, stringsAsFactors = FALSE)
  })
  features <- do.call(rbind, feature_rows)
  site_rows <- lapply(seq_len(nrow(missed)), function(i) {
    inside <- vapply(predictors, function(feature) missed[[feature]][i] >= features$background_q05[features$feature == feature] & missed[[feature]][i] <= features$background_q95[features$feature == feature], logical(1L))
    data.frame(feature_set = feature_set, row_id = missed[[context$config$columns$row_id]][i], site_id = missed[[context$config$columns$site_id]][i], regional_branch_id = missed$.regional_branch_id[i], observed_sr = missed$.observed[i],
      predictors_in_background_interval = sum(inside), predictor_count = length(predictors), background_interval_fraction = mean(inside), stringsAsFactors = FALSE)
  })
  sites <- do.call(rbind, site_rows)
  branches <- aggregate(background_interval_fraction ~ feature_set + regional_branch_id, sites, function(x) c(n = length(x), median = stats::median(x), min = min(x), max = max(x)))
  expanded <- data.frame(feature_set = branches$feature_set, regional_branch_id = branches$regional_branch_id,
    missed_high_sr_sites = branches$background_interval_fraction[, "n"], median_background_interval_fraction = branches$background_interval_fraction[, "median"],
    min_background_interval_fraction = branches$background_interval_fraction[, "min"], max_background_interval_fraction = branches$background_interval_fraction[, "max"], stringsAsFactors = FALSE)
  list(features = features, sites = sites, branches = expanded,
       summary = list(feature_set = feature_set, missed_sites = nrow(missed), predictor_count = length(predictors), median_site_background_interval_fraction = stats::median(sites$background_interval_fraction),
                      strong_features = sum(features$strong_univariate_discrimination), low_overlap_features = sum(features$low_background_overlap), strong_and_low_overlap_features = sum(features$strong_and_low_overlap)))
}
