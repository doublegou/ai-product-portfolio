rrisk_pr_auc <- function(truth, probability) {
  truth <- as.logical(truth); probability <- as.numeric(probability)
  valid <- !is.na(truth) & is.finite(probability); truth <- truth[valid]; probability <- probability[valid]
  if (!any(truth) || all(truth)) return(NA_real_)
  as.numeric(PRROC::pr.curve(scores.class0 = probability[truth], scores.class1 = probability[!truth], curve = FALSE)$auc.integral)
}

rrisk_roc_auc <- function(truth, probability) {
  truth <- as.logical(truth); probability <- as.numeric(probability)
  valid <- !is.na(truth) & is.finite(probability); truth <- truth[valid]; probability <- probability[valid]
  if (!any(truth) || all(truth)) return(NA_real_)
  as.numeric(pROC::auc(pROC::roc(truth, probability, levels = c(FALSE, TRUE), direction = "<", quiet = TRUE)))
}

rrisk_metrics <- function(truth, probability, context) {
  truth <- as.integer(truth); probability <- as.numeric(probability)
  rrisk_assert(length(truth) == length(probability) && all(truth %in% 0:1) && all(is.finite(probability)), "Metric inputs are invalid.")
  epsilon <- as.numeric(context$config$model$probability_clip)
  clipped <- pmin(pmax(probability, epsilon), 1 - epsilon)
  data.frame(
    n = length(truth), n_positive = sum(truth == 1L), n_negative = sum(truth == 0L),
    pr_auc = rrisk_pr_auc(truth == 1L, probability), roc_auc = rrisk_roc_auc(truth == 1L, probability),
    brier = mean((probability - truth)^2),
    log_loss = -mean(truth * log(clipped) + (1 - truth) * log(1 - clipped)), stringsAsFactors = FALSE
  )
}

rrisk_pooled_metrics <- function(oof, context) {
  do.call(rbind, lapply(split(oof, oof$model_id), function(x) cbind(
    data.frame(model_id = x$model_id[[1L]], model_type = x$model_type[[1L]], feature_set = x$feature_set[[1L]], stringsAsFactors = FALSE),
    rrisk_metrics(x$high_sr_label, x$p_high, context)
  )))
}

rrisk_mixed_branch_metrics <- function(oof, label_audit, context) {
  mixed <- label_audit$regional_branch_id[label_audit$branch_class == "mixed"]
  records <- list(); index <- 0L
  for (model in unique(oof$model_id)) for (branch in mixed) {
    x <- oof[oof$model_id == model & oof$regional_branch_id == branch, , drop = FALSE]
    index <- index + 1L
    records[[index]] <- cbind(
      data.frame(model_id = model, regional_branch_id = branch, outer_fold = unique(x$outer_fold), stringsAsFactors = FALSE),
      rrisk_metrics(x$high_sr_label, x$p_high, context),
      data.frame(
        positive_mean_score = mean(x$p_high[x$high_sr_label == 1L]), negative_mean_score = mean(x$p_high[x$high_sr_label == 0L]),
        positive_mean_above_negative = mean(x$p_high[x$high_sr_label == 1L]) > mean(x$p_high[x$high_sr_label == 0L]), stringsAsFactors = FALSE
      )
    )
  }
  do.call(rbind, records)
}

rrisk_mixed_macro_metrics <- function(branch_metrics) {
  do.call(rbind, lapply(split(branch_metrics, branch_metrics$model_id), function(x) data.frame(
    model_id = x$model_id[[1L]], mixed_branches = nrow(x), macro_pr_auc = mean(x$pr_auc, na.rm = TRUE),
    macro_roc_auc = mean(x$roc_auc, na.rm = TRUE), macro_brier = mean(x$brier), macro_log_loss = mean(x$log_loss),
    branches_positive_mean_above_negative = sum(x$positive_mean_above_negative),
    branches_positive_mean_above_negative_fraction = mean(x$positive_mean_above_negative), stringsAsFactors = FALSE
  )))
}

rrisk_positive_branch_coverage <- function(oof, label_audit) {
  positive_branches <- label_audit$regional_branch_id[label_audit$n_positive > 0L]
  do.call(rbind, lapply(split(oof, oof$model_id), function(x) {
    by_branch <- do.call(rbind, lapply(split(x[x$regional_branch_id %in% positive_branches, ], x$regional_branch_id[x$regional_branch_id %in% positive_branches]), function(z) data.frame(
      regional_branch_id = z$regional_branch_id[[1L]], n_positive = sum(z$high_sr_label == 1L),
      positive_mean_score = mean(z$p_high[z$high_sr_label == 1L]), branch_mean_score = mean(z$p_high), stringsAsFactors = FALSE
    )))
    data.frame(
      model_id = x$model_id[[1L]], positive_branches = nrow(by_branch),
      mean_positive_score_across_positive_branches = mean(by_branch$positive_mean_score),
      min_positive_branch_mean_score = min(by_branch$positive_mean_score), max_positive_branch_mean_score = max(by_branch$positive_mean_score),
      stringsAsFactors = FALSE
    )
  }))
}

rrisk_leave_one_branch_sensitivity <- function(oof, context) {
  records <- list(); index <- 0L
  for (model in unique(oof$model_id)) for (branch in unique(oof$regional_branch_id)) {
    x <- oof[oof$model_id == model & oof$regional_branch_id != branch, , drop = FALSE]
    index <- index + 1L
    records[[index]] <- cbind(data.frame(model_id = model, omitted_branch = branch, stringsAsFactors = FALSE), rrisk_metrics(x$high_sr_label, x$p_high, context))
  }
  do.call(rbind, records)
}

rrisk_branch_bootstrap <- function(oof, context) {
  branches <- sort(unique(oof$regional_branch_id)); models <- unique(oof$model_id)
  replicates <- as.integer(context$config$uncertainty$branch_bootstrap_replicates)
  set.seed(as.integer(context$config$uncertainty$branch_bootstrap_seed))
  records <- vector("list", replicates * length(models)); index <- 0L
  for (bootstrap_id in seq_len(replicates)) {
    sampled <- sample(branches, length(branches), replace = TRUE)
    for (model in models) {
      base <- oof[oof$model_id == model, , drop = FALSE]
      x <- do.call(rbind, lapply(sampled, function(branch) base[base$regional_branch_id == branch, , drop = FALSE]))
      index <- index + 1L
      records[[index]] <- cbind(data.frame(bootstrap_id = bootstrap_id, model_id = model, stringsAsFactors = FALSE), rrisk_metrics(x$high_sr_label, x$p_high, context))
    }
  }
  do.call(rbind, records)
}

rrisk_bootstrap_intervals <- function(bootstrap, context) {
  alpha <- 1 - as.numeric(context$config$uncertainty$confidence_level)
  metrics <- c("pr_auc", "roc_auc", "brier", "log_loss")
  records <- list(); index <- 0L
  for (model in unique(bootstrap$model_id)) for (metric in metrics) {
    values <- bootstrap[bootstrap$model_id == model, metric]
    index <- index + 1L
    records[[index]] <- data.frame(
      model_id = model, metric = metric, bootstrap_mean = mean(values, na.rm = TRUE),
      ci_lower = unname(stats::quantile(values, alpha / 2, na.rm = TRUE)),
      ci_upper = unname(stats::quantile(values, 1 - alpha / 2, na.rm = TRUE)), stringsAsFactors = FALSE
    )
  }
  do.call(rbind, records)
}

rrisk_paired_contrasts <- function(pooled, bootstrap, context) {
  models <- as.character(pooled$model_id); pairs <- utils::combn(models, 2L, simplify = FALSE)
  alpha <- 1 - as.numeric(context$config$uncertainty$confidence_level)
  metrics <- c("pr_auc", "roc_auc", "brier", "log_loss")
  records <- list(); index <- 0L
  for (pair in pairs) for (metric in metrics) {
    a <- bootstrap[bootstrap$model_id == pair[[1L]], c("bootstrap_id", metric)]; names(a)[[2L]] <- "a"
    b <- bootstrap[bootstrap$model_id == pair[[2L]], c("bootstrap_id", metric)]; names(b)[[2L]] <- "b"
    joined <- merge(a, b, by = "bootstrap_id", sort = TRUE); delta <- joined$a - joined$b
    point <- pooled[pooled$model_id == pair[[1L]], metric] - pooled[pooled$model_id == pair[[2L]], metric]
    index <- index + 1L
    records[[index]] <- data.frame(
      model_a = pair[[1L]], model_b = pair[[2L]], metric = metric, delta_definition = "model_a_minus_model_b",
      point_delta = point, bootstrap_delta_mean = mean(delta, na.rm = TRUE),
      ci_lower = unname(stats::quantile(delta, alpha / 2, na.rm = TRUE)),
      ci_upper = unname(stats::quantile(delta, 1 - alpha / 2, na.rm = TRUE)), stringsAsFactors = FALSE
    )
  }
  do.call(rbind, records)
}
