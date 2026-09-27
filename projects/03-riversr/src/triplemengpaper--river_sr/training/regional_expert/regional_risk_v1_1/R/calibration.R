rrisk11_clip_probability <- function(probability, epsilon) {
  pmin(1 - epsilon, pmax(epsilon, as.numeric(probability)))
}

rrisk11_fit_platt <- function(inner_oof, context) {
  required <- c("high_sr_label", "raw_probability", "branch_sqrt_weight")
  rrisk11_assert(length(setdiff(required, names(inner_oof))) == 0L, "Inner OOF lacks Platt calibration columns.")
  epsilon <- as.numeric(context$config$calibration$probability_clip)
  clipped <- rrisk11_clip_probability(inner_oof$raw_probability, epsilon)
  calibration_data <- data.frame(
    label = as.integer(inner_oof$high_sr_label), logit_raw_probability = stats::qlogis(clipped),
    weight = as.numeric(inner_oof$branch_sqrt_weight)
  )
  rrisk11_assert(setequal(unique(calibration_data$label), 0:1), "Platt calibration requires both classes.")
  rrisk11_assert(all(is.finite(calibration_data$logit_raw_probability)) && all(is.finite(calibration_data$weight)) && all(calibration_data$weight > 0), "Platt inputs are invalid.")
  warnings <- character()
  fitted <- withCallingHandlers(
    stats::glm(label ~ logit_raw_probability, data = calibration_data, weights = weight, family = stats::binomial()),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }
  )
  coefficients <- stats::coef(fitted)
  rrisk11_assert(isTRUE(fitted$converged) && length(coefficients) == 2L && all(is.finite(coefficients)), "Platt calibrator did not converge to finite coefficients.")
  slope <- unname(coefficients[[2L]])
  if (isTRUE(context$config$calibration$require_positive_slope)) rrisk11_assert(slope > 0, "Platt calibrator slope must be positive.")
  row <- data.frame(
    method = as.character(context$config$calibration$method), predictor = as.character(context$config$calibration$predictor),
    probability_clip = epsilon, intercept = unname(coefficients[[1L]]), slope = slope, converged = isTRUE(fitted$converged),
    positive_slope = slope > 0, n = nrow(calibration_data), n_positive = sum(calibration_data$label == 1L),
    weight_sum = sum(calibration_data$weight), warning_count = length(warnings), warnings = paste(unique(warnings), collapse = " | "),
    stringsAsFactors = FALSE
  )
  list(intercept = row$intercept[[1L]], slope = row$slope[[1L]], summary = row)
}

rrisk11_apply_platt <- function(raw_probability, calibrator, context) {
  epsilon <- as.numeric(context$config$calibration$probability_clip)
  x <- stats::qlogis(rrisk11_clip_probability(raw_probability, epsilon))
  calibrated <- stats::plogis(calibrator$intercept + calibrator$slope * x)
  rrisk11_assert(length(calibrated) == length(raw_probability) && all(is.finite(calibrated)), "Platt mapping returned invalid probabilities.")
  calibrated
}

rrisk11_check_platt_interface <- function(context) {
  branch <- rep(sprintf("b%02d", 1:6), each = 12L)
  label <- as.integer(seq_along(branch) > length(branch) / 2)
  label[c(10L, 20L, 30L, 43L, 53L, 63L)] <- 1L - label[c(10L, 20L, 30L, 43L, 53L, 63L)]
  raw <- rrisk11_clip_probability(seq(0.03, 0.97, length.out = length(label)) + rep(c(-0.01, 0.01), length.out = length(label)), 1e-6)
  sizes <- table(branch)
  weights <- (1 / sqrt(as.numeric(sizes[branch])))
  synthetic <- data.frame(high_sr_label = label, raw_probability = raw, branch_sqrt_weight = weights / mean(weights))
  calibrator <- rrisk11_fit_platt(synthetic, context)
  mapped <- rrisk11_apply_platt(raw, calibrator, context)
  rrisk11_assert(calibrator$slope > 0 && all(mapped > 0 & mapped < 1), "Synthetic Platt contract failed.")
  invisible(TRUE)
}
