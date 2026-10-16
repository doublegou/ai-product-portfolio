stage_fa_summarize <- function(context) {
  required <- c("audit_manifest.json", "full64_feature_overlap.csv", "process14_feature_overlap.csv", "nearest_neighbor_summary.csv")
  fa_assert(all(file.exists(fa_results_path(context, required))), "Run --stage audit before summarization.")
  validated <- fa_validate_inputs(context)
  manifest <- jsonlite::read_json(fa_results_path(context, "audit_manifest.json"), simplifyVector = FALSE)
  full_features <- fa_read_csv(fa_results_path(context, "full64_feature_overlap.csv")); full_sites <- fa_read_csv(fa_results_path(context, "full64_site_overlap.csv"))
  process_features <- fa_read_csv(fa_results_path(context, "process14_feature_overlap.csv")); process_sites <- fa_read_csv(fa_results_path(context, "process14_site_overlap.csv")); nn <- fa_read_csv(fa_results_path(context, "nearest_neighbor_summary.csv"))
  summary_from <- function(features, sites, feature_set) list(feature_set = feature_set, predictor_count = nrow(features), missed_sites = nrow(sites), median_site_background_interval_fraction = stats::median(sites$background_interval_fraction),
    strong_features = sum(as.logical(features$strong_univariate_discrimination)), low_overlap_features = sum(as.logical(features$low_background_overlap)), strong_and_low_overlap_features = sum(as.logical(features$strong_and_low_overlap)))
  full_nn_summary <- nn[nn$feature_set == "full64", ]; process_nn_summary <- nn[nn$feature_set == "process14", ]
  audit <- list(validated = validated, full64_overlap = list(summary = summary_from(full_features, full_sites, "full64")), process14_overlap = list(summary = summary_from(process_features, process_sites, "process14")),
    full64_nn = list(summary = full_nn_summary), process14_nn = list(summary = process_nn_summary), manifest = manifest)
  lines <- fa_failure_markdown(context, audit); fa_write_text(lines, fa_results_path(context, "FAILURE_AUDIT.md")); fa_log("Failure Audit summary written; Regional Risk V2 remains closed.")
  invisible(lines)
}
