river_sr_packages <- list(
  infrastructure = c(
    "renv", "yaml", "jsonlite", "digest", "fs", "here", "cli"
  ),
  pipeline = c(
    "targets", "tarchetypes", "future", "future.apply"
  ),
  data = c(
    "data.table", "readr", "dplyr", "tidyr", "purrr", "tibble"
  ),
  spatial = c(
    "sf", "terra", "units", "lwgeom", "exactextractr"
  ),
  modelling = c(
    "ranger", "randomForest", "glmnet", "xgboost", "mgcv",
    "rsample", "recipes", "yardstick", "pROC", "PRROC"
  ),
  reporting = c(
    "ggplot2", "rmarkdown", "knitr"
  ),
  testing = c(
    "testthat", "withr"
  )
)
