v0_calculate_metrics <- function(observed, predicted) {
  observed <- as.numeric(observed)
  predicted <- as.numeric(predicted)
  valid <- is.finite(observed) & is.finite(predicted)
  observed <- observed[valid]
  predicted <- predicted[valid]
  n <- length(observed)
  if (n == 0L) {
    return(data.frame(n = 0L, rmse = NA_real_, mae = NA_real_, r2 = NA_real_, bias = NA_real_))
  }
  residual <- predicted - observed
  denominator <- sum((observed - mean(observed))^2)
  data.frame(
    n = n,
    rmse = sqrt(mean(residual^2)),
    mae = mean(abs(residual)),
    r2 = if (denominator <= 0) NA_real_ else 1 - sum(residual^2) / denominator,
    bias = mean(residual)
  )
}
