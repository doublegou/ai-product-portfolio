get_prefixed <- function(dat, prefix) names(dat)[startsWith(names(dat), prefix)]

resolve_predictor_sets <- function(dat, cfg) {
  p <- cfg$predictors$prefixes
  P0 <- get_prefixed(dat, p$P0)
  P1 <- c(P0, get_prefixed(dat, p$P1))
  P2A <- c(P1, get_prefixed(dat, p$P2A))
  P2Q <- c(P1, get_prefixed(dat, p$P2Q))
  P3A <- c(P2A, get_prefixed(dat, p$P3))
  P3Q <- c(P2Q, get_prefixed(dat, p$P3))
  sets <- list(A0=P0, A1=P1, A2_area=P2A, A3_runoff=P2Q, A4_area_hydro=P3A, A4_runoff_hydro=P3Q)
  sets <- sets[vapply(sets, length, integer(1)) > 0]
  if (!length(sets)) {
    stop(
      "No predictor columns found. Expected prefixes: ",
      paste(unlist(p), collapse=", "),
      "\nSee data/external/README.md"
    )
  }
  unique_sets <- list()
  seen <- character()
  for (nm in names(sets)) {
    key <- paste(sort(unique(sets[[nm]])), collapse="|")
    if (!key %in% seen) {
      unique_sets[[nm]] <- unique(sets[[nm]])
      seen <- c(seen, key)
    }
  }
  unique_sets
}

predictor_completeness <- function(dat, predictors) {
  if (!length(predictors)) return(0)
  mean(stats::complete.cases(dat[, predictors, drop=FALSE]))
}
