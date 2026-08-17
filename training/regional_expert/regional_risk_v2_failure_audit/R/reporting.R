fa_percent <- function(x, digits = 1L) sprintf(paste0("%.", digits, "f%%"), 100 * as.numeric(x))

fa_failure_markdown <- function(context, audit) {
  full_overlap <- audit$full64_overlap$summary; process_overlap <- audit$process14_overlap$summary
  primary_k <- as.integer(context$config$nearest_neighbor_audit$primary_k)
  full_nn <- audit$full64_nn$summary[audit$full64_nn$summary$k == primary_k, , drop = FALSE]
  process_nn <- audit$process14_nn$summary[audit$process14_nn$summary$k == primary_k, , drop = FALSE]
  recovered <- context$config$recovered_reference_values
  conclusion <- "The shared failure of GAM, RF, and XGBoost is primarily an information problem rather than an algorithm-selection problem. The current 64-dimensional predictor space does not adequately encode the mechanisms responsible for a subset of high-Sr systems."
  c(
    "# Regional Risk V2 Failure Audit", "", "## Status", "", "`STRUCTURAL_INFORMATION_GAP_SUPPORTED`", "",
    "This read-only audit begins from the frozen Regional Risk V2 Outer OOF result. It does not train a model, change a threshold or reopen Gate selection.", "",
    "## Frozen failure set", "",
    paste0("The closest V2 candidate, `", context$config$failure_set$primary_candidate, "`, completely missed ", length(audit$validated$missed_branches),
           " positive branches containing ", length(audit$validated$missed_ids), " high-Sr sites. A branch is completely missed when none of its `Sr >= 0.75` sites is triggered in strict Outer OOF."), "",
    "## 1. Full64 background-overlap audit", "",
    paste0("Across the missed high-Sr sites, the median fraction of 64 predictors falling inside the ordinary-background 5th-95th percentile interval was ", fa_percent(full_overlap$median_site_background_interval_fraction), "."),
    paste0("Features meeting the prespecified strong univariate discrimination rule: ", full_overlap$strong_features, "/", full_overlap$predictor_count, "."),
    paste0("Features simultaneously showing strong univariate discrimination and low background overlap: ", full_overlap$strong_and_low_overlap_features, "/", full_overlap$predictor_count, "."), "",
    "## 2. Cross-branch nearest-neighbor audit", "",
    paste0("Using robust-scaled Full64 Euclidean distance, excluding every query site's own branch, the high-Sr fraction among the ", primary_k, " nearest neighbors was ",
           fa_percent(full_nn$high_sr_neighbor_fraction_station_equal), " (station-equal) and ", fa_percent(full_nn$high_sr_neighbor_fraction_branch_sqrt), " (branch-sqrt edge-weighted)."),
    paste0("The corresponding global high-Sr baselines were ", fa_percent(full_nn$global_high_sr_fraction_station_equal), " and ", fa_percent(full_nn$global_high_sr_fraction_branch_sqrt), "."),
    "The nearest neighborhoods of the missed high-Sr sites therefore do not show a stronger high-Sr composition than the domain baseline.", "",
    "## 3. Process14 failure-case audit", "",
    paste0("Within Process14 alone, the median missed-site background-interval fraction was ", fa_percent(process_overlap$median_site_background_interval_fraction), "; ",
           process_overlap$strong_and_low_overlap_features, "/14 features simultaneously met the strong-discrimination and low-overlap rules."),
    paste0("The Process14 cross-branch ", primary_k, "-neighbor high-Sr fractions were ", fa_percent(process_nn$high_sr_neighbor_fraction_station_equal), " (station-equal) and ",
           fa_percent(process_nn$high_sr_neighbor_fraction_branch_sqrt), " (branch-sqrt edge-weighted)."),
    "Process14 is therefore a representative failure case: its process proxies are present, but the missed high-Sr systems remain embedded in background-like predictor neighborhoods.", "",
    "## Historical-context boundary", "",
    paste0("The recovered audit narrative reported ", recovered$missed_branches, " missed branches, ", recovered$missed_high_sr_sites, " missed sites, median overlap ",
           fa_percent(recovered$median_background_interval_fraction), ", and high-Sr neighbor composition ", fa_percent(recovered$cross_branch_high_sr_neighbor_fraction),
           " against a ", fa_percent(recovered$global_high_sr_station_fraction), " station baseline."),
    "Those values are context only. The findings above are recomputed from the present frozen V2 OOF and its own failure set.", "",
    "## Conclusion", "", conclusion, "",
    "This result closes Regional Risk V2. It does not justify another RF/XGBoost tuning cycle on the same 64 predictors. The next architecture must introduce genuinely new regional, branch, geological, watershed, hydrogeochemical, spatial-context or process-specific information, with the exact new inputs determined by a separate data audit.", "",
    "Process14 has two distinct roles: here it is a failure diagnosis; in a future expert project it may serve as a prototype only if additional region/process-specific information is introduced. Re-fitting the same 64 variables within a region would not resolve the demonstrated representation gap.", "",
    "## Provenance", "",
    paste0("- Source V2 data MD5: `", audit$validated$signatures$table$md5, "`"),
    paste0("- Source Outer OOF MD5: `", audit$validated$signatures$outer_oof$md5, "`"),
    paste0("- Primary candidate: `", context$config$failure_set$primary_candidate, "`"),
    paste0("- Missed branches/sites: ", length(audit$validated$missed_branches), "/", length(audit$validated$missed_ids)),
    "- Model training performed: `false`", "- Gate or threshold modified: `false`", "- Full-data model fitted: `false`", "- Release created: `false`"
  )
}
