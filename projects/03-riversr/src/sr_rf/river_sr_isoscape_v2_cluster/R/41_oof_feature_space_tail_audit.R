suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

dat <- readRDS(
  "data/processed/model_table_p0_full_range.rds"
)

folds <- readRDS(
  "data/processed/folds_long.rds"
) |>
  filter(
    scheme == "spatial_1500km"
  ) |>
  select(
    row_id,
    outer_fold = fold,
    block_id
  )

out_dir <-
  "outputs/experiment_p0_full_range_1500/feature_space_tail_audit"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

p0_all <- grep(
  "^p0__",
  names(dat),
  value = TRUE
)

stopifnot(
  length(p0_all) == 28L
)

p0_process <- setdiff(
  p0_all,
  c(
    "p0__sp_x",
    "p0__sp_y",
    "p0__sp_z"
  )
)

stopifnot(
  length(p0_process) == 25L
)

complete_index <- complete.cases(
  dat[, p0_all, drop = FALSE]
)

dat <- dat[
  complete_index,
  ,
  drop = FALSE
] |>
  left_join(
    folds,
    by = "row_id"
  )

if (nrow(dat) != 4485L) {
  stop(
    "Expected 4485 rows, got ",
    nrow(dat)
  )
}

if (anyNA(dat$outer_fold)) {
  stop(
    "Missing outer-fold assignments."
  )
}

# ------------------------------------------------------------
# Robust scaling
# fitted ONLY from each target's available outer-training data
# ------------------------------------------------------------

robust_scale_train <- function(train_x, test_x) {

  med <- apply(
    train_x,
    2,
    median,
    na.rm = TRUE
  )

  scl <- apply(
    train_x,
    2,
    IQR,
    na.rm = TRUE
  )

  bad <- !is.finite(scl) |
    scl <= 0

  if (any(bad)) {

    sd_alt <- apply(
      train_x[, bad, drop = FALSE],
      2,
      sd,
      na.rm = TRUE
    )

    scl[bad] <- sd_alt
  }

  bad2 <- !is.finite(scl) |
    scl <= 0

  scl[bad2] <- 1

  train_scaled <- sweep(
    train_x,
    2,
    med,
    "-"
  )

  train_scaled <- sweep(
    train_scaled,
    2,
    scl,
    "/"
  )

  test_scaled <- (
    as.numeric(test_x) -
      med
  ) / scl

  list(
    train = train_scaled,
    test = test_scaled
  )
}

# ------------------------------------------------------------
# OOF nearest-neighbour audit
# ------------------------------------------------------------

audit_one <- function(
    feature_names,
    feature_set_name,
    target_threshold,
    k = 10L) {

  targets <- dat |>
    filter(
      sr87_sr86 >= target_threshold
    )

  output <- vector(
    "list",
    nrow(targets)
  )

  neighbor_output <- list()

  neighbor_counter <- 1L

  for (i in seq_len(nrow(targets))) {

    target <- targets[i, ]

    train <- dat |>
      filter(
        outer_fold !=
          target$outer_fold
      )

    train_x <- as.matrix(
      train[
        ,
        feature_names,
        drop = FALSE
      ]
    )

    test_x <- as.numeric(
      unlist(
        target[
          1,
          feature_names,
          drop = FALSE
        ],
        use.names = FALSE
      )
    )

    storage.mode(train_x) <-
      "numeric"

    scaled <- robust_scale_train(
      train_x,
      test_x
    )

    delta <- sweep(
      scaled$train,
      2,
      scaled$test,
      "-"
    )

    distance <- sqrt(
      rowSums(
        delta^2
      )
    )

    ord <- order(
      distance
    )

    take <- ord[
      seq_len(
        min(
          k,
          length(ord)
        )
      )
    ]

    nn <- train[
      take,
      ,
      drop = FALSE
    ]

    nn$distance <-
      distance[take]

    nn$neighbor_rank <-
      seq_len(
        nrow(nn)
      )

    nn$target_row_id <-
      target$row_id

    nn$target_sr <-
      target$sr87_sr86

    nn$target_fold <-
      target$outer_fold

    nn$feature_set <-
      feature_set_name

    nn$target_threshold <-
      target_threshold

    neighbor_output[[
      neighbor_counter
    ]] <- nn |>
      select(
        feature_set,
        target_threshold,
        target_row_id,
        target_sr,
        target_fold,
        neighbor_rank,
        row_id,
        sr87_sr86,
        outer_fold,
        block_id,
        distance
      )

    neighbor_counter <-
      neighbor_counter + 1L

    output[[i]] <-
      data.frame(
        feature_set =
          feature_set_name,

        threshold =
          target_threshold,

        row_id =
          target$row_id,

        target_sr =
          target$sr87_sr86,

        outer_fold =
          target$outer_fold,

        nearest_distance =
          min(nn$distance),

        mean_nn_distance =
          mean(nn$distance),

        mean_nn_sr =
          mean(nn$sr87_sr86),

        median_nn_sr =
          median(nn$sr87_sr86),

        max_nn_sr =
          max(nn$sr87_sr86),

        min_nn_sr =
          min(nn$sr87_sr86),

        n_nn_ge_072 =
          sum(
            nn$sr87_sr86 >= 0.720
          ),

        n_nn_ge_075 =
          sum(
            nn$sr87_sr86 >= 0.750
          ),

        n_nn_ge_080 =
          sum(
            nn$sr87_sr86 >= 0.800
          )
      )
  }

  list(
    targets =
      bind_rows(output),

    neighbors =
      bind_rows(
        neighbor_output
      )
  )
}

# ------------------------------------------------------------
# Run four audits
# ------------------------------------------------------------

a75_process <- audit_one(
  p0_process,
  "PROCESS25",
  0.750,
  10L
)

a80_process <- audit_one(
  p0_process,
  "PROCESS25",
  0.800,
  10L
)

a75_all <- audit_one(
  p0_all,
  "ALL28",
  0.750,
  10L
)

a80_all <- audit_one(
  p0_all,
  "ALL28",
  0.800,
  10L
)

target_summary <- bind_rows(
  a75_process$targets,
  a80_process$targets,
  a75_all$targets,
  a80_all$targets
)

neighbor_detail <- bind_rows(
  a75_process$neighbors,
  a80_process$neighbors,
  a75_all$neighbors,
  a80_all$neighbors
)

write_csv(
  target_summary,
  file.path(
    out_dir,
    "target_nearest_neighbor_summary.csv"
  )
)

write_csv(
  neighbor_detail,
  file.path(
    out_dir,
    "nearest_neighbor_details.csv"
  )
)

# ------------------------------------------------------------
# Aggregate separability summary
# ------------------------------------------------------------

aggregate_summary <- target_summary |>
  group_by(
    feature_set,
    threshold
  ) |>
  summarise(
    n_targets =
      n(),

    mean_target_sr =
      mean(target_sr),

    mean_nn_sr =
      mean(mean_nn_sr),

    median_nn_sr =
      median(median_nn_sr),

    mean_max_nn_sr =
      mean(max_nn_sr),

    median_nearest_distance =
      median(nearest_distance),

    mean_n_nn_ge_072 =
      mean(n_nn_ge_072),

    mean_n_nn_ge_075 =
      mean(n_nn_ge_075),

    mean_n_nn_ge_080 =
      mean(n_nn_ge_080),

    pct_targets_with_any_nn_ge_075 =
      mean(
        n_nn_ge_075 > 0
      ) * 100,

    pct_targets_with_any_nn_ge_080 =
      mean(
        n_nn_ge_080 > 0
      ) * 100,

    .groups = "drop"
  )

write_csv(
  aggregate_summary,
  file.path(
    out_dir,
    "feature_space_separability_summary.csv"
  )
)

cat(
  "\n===== FEATURE-SPACE SEPARABILITY =====\n"
)

print(
  as.data.frame(aggregate_summary),
  row.names = FALSE
)

# ------------------------------------------------------------
# Show the most extreme >=0.800 sites
# ------------------------------------------------------------

extreme_summary <- target_summary |>
  filter(
    threshold == 0.800
  ) |>
  arrange(
    feature_set,
    desc(target_sr)
  )

cat(
  "\n===== EXTREME TARGET SUMMARY =====\n"
)

print(
  as.data.frame(extreme_summary),
  row.names = FALSE
)

# ------------------------------------------------------------
# Show 10 NN for five most extreme sites
# PROCESS25 only
# ------------------------------------------------------------

top5_ids <- dat |>
  filter(
    sr87_sr86 >= 0.800
  ) |>
  arrange(
    desc(sr87_sr86)
  ) |>
  slice_head(
    n = 5
  ) |>
  pull(
    row_id
  )

top5_neighbors <- neighbor_detail |>
  filter(
    feature_set == "PROCESS25",
    target_threshold == 0.800,
    target_row_id %in% top5_ids
  ) |>
  arrange(
    desc(target_sr),
    neighbor_rank
  )

cat(
  "\n===== PROCESS25: 10 OOF NEIGHBORS OF TOP-5 EXTREMES =====\n"
)

print(
  as.data.frame(top5_neighbors),
  row.names = FALSE
)

write_csv(
  top5_neighbors,
  file.path(
    out_dir,
    "top5_extreme_process25_neighbors.csv"
  )
)

cat(
  "\n===== DONE =====\n"
)

cat(
  "Saved to: ",
  out_dir,
  "\n",
  sep = ""
)
