library(dplyr)
library(readr)
library(ranger)
library(Cubist)
library(tibble)

set.seed(20260727)

dat <- readRDS(
  "data/processed/model_table.rds"
)

folds <- readRDS(
  "data/processed/folds_long.rds"
)

predictors <- grep(
  "^p0__",
  names(dat),
  value = TRUE
)

stopifnot(
  length(predictors) == 28
)

dat <- dat |>
  filter(
    complete.cases(
      across(
        all_of(
          c("sr87_sr86", predictors)
        )
      )
    )
  )

stopifnot(
  nrow(dat) == 4465
)

fold_one <- folds |>
  filter(
    scheme == "spatial_500km"
  ) |>
  select(
    row_id,
    outer_fold = fold
  )

dat <- dat |>
  inner_join(
    fold_one,
    by = "row_id"
  )

stopifnot(
  nrow(dat) == 4465,
  !anyNA(dat$outer_fold)
)

train <- dat |>
  filter(outer_fold != 1)

test <- dat |>
  filter(outer_fold == 1)

cat(
  "Training rows:",
  nrow(train),
  "\n"
)

cat(
  "Test rows:",
  nrow(test),
  "\n"
)

cat(
  "Predictors:",
  length(predictors),
  "\n"
)

metric_row <- function(
    observed,
    predicted,
    algorithm
) {
  residual <- predicted - observed

  high <- observed >= 0.720

  tibble(
    algorithm = algorithm,
    n_train = nrow(train),
    n_test = length(observed),
    rmse = sqrt(
      mean(
        residual^2,
        na.rm = TRUE
      )
    ),
    mae = mean(
      abs(residual),
      na.rm = TRUE
    ),
    bias = mean(
      residual,
      na.rm = TRUE
    ),
    high_n = sum(high),
    high_rmse = sqrt(
      mean(
        residual[high]^2,
        na.rm = TRUE
      )
    ),
    high_bias = mean(
      residual[high],
      na.rm = TRUE
    ),
    observed_min = min(observed),
    observed_max = max(observed),
    predicted_min = min(predicted),
    predicted_max = max(predicted),
    correlation = cor(
      observed,
      predicted,
      use = "complete.obs"
    )
  )
}

# ------------------------------------------------------------
# Random forest smoke test
# ------------------------------------------------------------

rf_formula <- stats::reformulate(
  predictors,
  response = "sr87_sr86"
)

rf_model <- ranger::ranger(
  formula = rf_formula,
  data = train,
  num.trees = 300,
  mtry = max(
    1L,
    floor(
      sqrt(
        length(predictors)
      )
    )
  ),
  min.node.size = 5,
  importance = "permutation",
  num.threads = 4,
  seed = 20260727
)

rf_prediction <- predict(
  rf_model,
  data = test
)$predictions

stopifnot(
  length(rf_prediction) == nrow(test),
  all(is.finite(rf_prediction))
)

# ------------------------------------------------------------
# Cubist smoke test
# ------------------------------------------------------------

cubist_model <- Cubist::cubist(
  x = train[, predictors, drop = FALSE],
  y = train$sr87_sr86,
  committees = 10
)

cubist_prediction <- predict(
  cubist_model,
  newdata = test[, predictors, drop = FALSE],
  neighbors = 0
)

cubist_prediction <- as.numeric(
  cubist_prediction
)

stopifnot(
  length(cubist_prediction) == nrow(test),
  all(is.finite(cubist_prediction))
)

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------

predictions <- bind_rows(
  test |>
    transmute(
      row_id,
      outer_fold,
      algorithm = "RF",
      observed = sr87_sr86,
      predicted = rf_prediction
    ),

  test |>
    transmute(
      row_id,
      outer_fold,
      algorithm = "Cubist",
      observed = sr87_sr86,
      predicted = cubist_prediction
    )
)

metrics <- bind_rows(
  metric_row(
    test$sr87_sr86,
    rf_prediction,
    "RF"
  ),

  metric_row(
    test$sr87_sr86,
    cubist_prediction,
    "Cubist"
  )
)

dir.create(
  "outputs/experiment_A",
  recursive = TRUE,
  showWarnings = FALSE
)

write_csv(
  predictions,
  "outputs/experiment_A/p0_smoke_predictions.csv"
)

write_csv(
  metrics,
  "outputs/experiment_A/p0_smoke_metrics.csv"
)

saveRDS(
  list(
    rf = rf_model,
    cubist = cubist_model
  ),
  "outputs/experiment_A/p0_smoke_models.rds",
  compress = "xz"
)

print(metrics)

cat(
  "P0 RF/Cubist smoke test passed.\n"
)
