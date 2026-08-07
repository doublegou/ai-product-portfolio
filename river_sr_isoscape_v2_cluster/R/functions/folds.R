assign_balanced_folds <- function(
    block_id,
    high_flag,
    n_folds,
    seed = 1L,
    n_starts = 250L
) {
  if (length(block_id) != length(high_flag)) {
    stop("block_id and high_flag must have equal length.")
  }

  if (n_folds < 2L) {
    stop("n_folds must be at least 2.")
  }

  tab <- tibble::tibble(
    block_id = as.character(block_id),
    high_flag = as.integer(high_flag)
  ) |>
    dplyr::group_by(block_id) |>
    dplyr::summarise(
      n = dplyr::n(),
      n_high = sum(high_flag, na.rm = TRUE),
      .groups = "drop"
    )

  target_n <- sum(tab$n) / n_folds
  target_high <- sum(tab$n_high) / n_folds
  target_blocks <- nrow(tab) / n_folds

  score_assignment <- function(
      fold_n,
      fold_high,
      fold_blocks
  ) {
    n_dev <- max(
      abs(fold_n - target_n)
    ) / max(target_n, 1)

    high_dev <- max(
      abs(fold_high - target_high)
    ) / max(target_high, 1)

    block_dev <- max(
      abs(fold_blocks - target_blocks)
    ) / max(target_blocks, 1)

    # High-Sr balance receives the largest weight.
    2 * high_dev +
      n_dev +
      0.05 * block_dev
  }

  best_score <- Inf
  best_assignment <- NULL

  for (start_index in seq_len(n_starts)) {
    set.seed(
      as.integer(seed) +
        as.integer(start_index) -
        1L
    )

    tab_i <- tab |>
      dplyr::mutate(
        difficulty =
          n_high / max(target_high, 1) +
          n / max(target_n, 1),

        # Slightly vary ordering across restarts.
        priority =
          difficulty +
          stats::runif(
            dplyr::n(),
            min = 0,
            max = 0.05
          )
      ) |>
      dplyr::arrange(
        dplyr::desc(priority),
        dplyr::desc(n_high),
        dplyr::desc(n)
      )

    fold_n <- numeric(n_folds)
    fold_high <- numeric(n_folds)
    fold_blocks <- integer(n_folds)
    assignment <- integer(nrow(tab_i))

    for (i in seq_len(nrow(tab_i))) {
      candidate_scores <- vapply(
        seq_len(n_folds),
        function(f) {
          next_n <- fold_n
          next_high <- fold_high
          next_blocks <- fold_blocks

          next_n[f] <-
            next_n[f] +
            tab_i$n[i]

          next_high[f] <-
            next_high[f] +
            tab_i$n_high[i]

          next_blocks[f] <-
            next_blocks[f] +
            1L

          score_assignment(
            next_n,
            next_high,
            next_blocks
          )
        },
        numeric(1)
      )

      best_folds <- which(
        candidate_scores <=
          min(candidate_scores) +
          1e-12
      )

      # Random tie-breaking makes multiple restarts useful.
      chosen_fold <- if (
        length(best_folds) == 1L
      ) {
        best_folds
      } else {
        sample(best_folds, 1L)
      }

      assignment[i] <- chosen_fold

      fold_n[chosen_fold] <-
        fold_n[chosen_fold] +
        tab_i$n[i]

      fold_high[chosen_fold] <-
        fold_high[chosen_fold] +
        tab_i$n_high[i]

      fold_blocks[chosen_fold] <-
        fold_blocks[chosen_fold] +
        1L
    }

    final_score <- score_assignment(
      fold_n,
      fold_high,
      fold_blocks
    )

    if (final_score < best_score) {
      best_score <- final_score

      best_assignment <- stats::setNames(
        assignment,
        tab_i$block_id
      )
    }
  }

  if (is.null(best_assignment)) {
    stop("Failed to assign blocks to folds.")
  }

  best_assignment
}

make_spatial_folds <- function(dat, block_size_km, n_folds, crs_equal_area = 8857,
                               seed = 1L, tail_threshold = 0.720) {
  sf_pts <- sf::st_as_sf(dat, coords = c("longitude","latitude"), crs = 4326, remove = FALSE)
  xy <- sf::st_coordinates(sf::st_transform(sf_pts, crs_equal_area))
  size_m <- block_size_km * 1000
  block_x <- floor(xy[,1] / size_m)
  block_y <- floor(xy[,2] / size_m)
  block_id <- paste(block_x, block_y, sep = "_")
  fold_map <- assign_balanced_folds(block_id, dat$sr87_sr86 >= tail_threshold, n_folds, seed)
  tibble::tibble(
    row_id = dat$row_id,
    block_id = block_id,
    fold = unname(fold_map[block_id])
  )
}

make_reference_folds <- function(dat, n_folds, seed = 1L, tail_threshold = 0.720) {
  ref <- if ("reference_id" %in% names(dat)) dat$reference_id else safe_name(dat$short_references)
  fold_map <- assign_balanced_folds(ref, dat$sr87_sr86 >= tail_threshold, n_folds, seed)
  tibble::tibble(row_id = dat$row_id, block_id = ref, fold = unname(fold_map[ref]))
}
