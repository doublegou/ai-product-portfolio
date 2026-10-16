stage_fa_audit <- function(context) {
  validated <- fa_validate_inputs(context)
  full64_overlap <- fa_overlap_audit(validated, validated$full64, "full64", context)
  process14_overlap <- fa_overlap_audit(validated, validated$process14, "process14", context)
  full64_nn <- fa_nn_audit(validated, validated$full64, "full64", context)
  process14_nn <- fa_nn_audit(validated, validated$process14, "process14", context)
  missed_sites <- validated$data[validated$data$.failure_role == "missed_high_sr", c(context$config$columns$row_id, context$config$columns$site_id, ".regional_branch_id", ".observed"), drop = FALSE]
  names(missed_sites) <- c("row_id", "site_id", "regional_branch_id", "observed_sr")
  missed_branches <- aggregate(observed_sr ~ regional_branch_id, missed_sites, function(x) c(n = length(x), min = min(x), median = stats::median(x), max = max(x)))
  missed_branches <- data.frame(regional_branch_id = missed_branches$regional_branch_id, missed_high_sr_sites = missed_branches$observed_sr[, "n"], min_sr = missed_branches$observed_sr[, "min"], median_sr = missed_branches$observed_sr[, "median"], max_sr = missed_branches$observed_sr[, "max"], stringsAsFactors = FALSE)
  nn_summary <- rbind(full64_nn$summary, process14_nn$summary)
  outputs <- list(missed_branches = missed_branches, missed_high_sr_sites = missed_sites,
    full64_feature_overlap = full64_overlap$features, full64_site_overlap = full64_overlap$sites, full64_branch_overlap = full64_overlap$branches,
    process14_feature_overlap = process14_overlap$features, process14_site_overlap = process14_overlap$sites, process14_branch_overlap = process14_overlap$branches,
    nearest_neighbor_summary = nn_summary, full64_nearest_neighbor_edges = full64_nn$edges, process14_nearest_neighbor_edges = process14_nn$edges)
  for (name in names(outputs)) fa_write_csv(outputs[[name]], fa_results_path(context, paste0(name, ".csv")))
  audit <- list(validated = validated, full64_overlap = full64_overlap, process14_overlap = process14_overlap, full64_nn = full64_nn, process14_nn = process14_nn)
  manifest <- list(status = "complete", created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), project = context$config$project,
    inputs = validated$signatures, failure_set = list(primary_candidate = context$config$failure_set$primary_candidate, missed_branches = length(validated$missed_branches), missed_high_sr_sites = length(validated$missed_ids), branch_ids = validated$missed_branches),
    overlap = list(full64 = full64_overlap$summary, process14 = process14_overlap$summary), nearest_neighbor = list(primary_k = context$config$nearest_neighbor_audit$primary_k,
      full64 = full64_nn$summary[full64_nn$summary$k == as.integer(context$config$nearest_neighbor_audit$primary_k), ], process14 = process14_nn$summary[process14_nn$summary$k == as.integer(context$config$nearest_neighbor_audit$primary_k), ]),
    model_training_performed = FALSE, threshold_modified = FALSE, release_created = FALSE)
  fa_write_json(manifest, fa_results_path(context, "audit_manifest.json")); fa_log("Failure Audit computations complete; no model fitted.")
  invisible(audit)
}
