# Generic HydroBASINS downstream-accumulation functions.
#
# These functions do not depend on dplyr or sf and can therefore be reused
# by geological-age, bedrock-Sr, runoff and glacier predictor builders.

normalize_network_id <- function(x) {
  output <- rep(
    NA_character_,
    length(x)
  )

  nonmissing <- which(
    !is.na(x)
  )

  if (length(nonmissing) == 0L) {
    return(output)
  }

  raw_values <- trimws(
    as.character(
      x[nonmissing]
    )
  )

  numeric_values <- suppressWarnings(
    as.numeric(raw_values)
  )

  numeric_index <- is.finite(
    numeric_values
  )

  if (any(numeric_index)) {
    output[
      nonmissing[numeric_index]
    ] <- sprintf(
      "%.0f",
      numeric_values[numeric_index]
    )
  }

  if (any(!numeric_index)) {
    output[
      nonmissing[!numeric_index]
    ] <- raw_values[
      !numeric_index
    ]
  }

  output[
    output %in% c(
      "",
      "0",
      "NA",
      "NaN"
    )
  ] <- NA_character_

  output
}


build_downstream_index <- function(
    basin_id,
    next_down,
    external_action = c(
      "error",
      "warn",
      "outlet"
    )
) {
  external_action <- match.arg(
    external_action
  )

  if (
    length(basin_id) !=
      length(next_down)
  ) {
    stop(
      "basin_id and next_down must have equal length."
    )
  }

  id_key <- normalize_network_id(
    basin_id
  )

  next_key <- normalize_network_id(
    next_down
  )

  if (anyNA(id_key)) {
    stop(
      "Missing or invalid HYBAS_ID values."
    )
  }

  duplicated_id <- duplicated(
    id_key
  )

  if (any(duplicated_id)) {
    stop(
      "Duplicated HYBAS_ID values: ",
      paste(
        head(
          unique(
            id_key[duplicated_id]
          ),
          10
        ),
        collapse = ", "
      )
    )
  }

  id_lookup <- setNames(
    seq_along(id_key),
    id_key
  )

  downstream_index <- unname(
    id_lookup[next_key]
  )

  external_index <- which(
    !is.na(next_key) &
      is.na(downstream_index)
  )

  if (length(external_index) > 0L) {
    message_text <- paste0(
      length(external_index),
      " NEXT_DOWN IDs are outside the current basin table."
    )

    if (external_action == "error") {
      stop(message_text)
    }

    if (external_action == "warn") {
      warning(
        message_text,
        call. = FALSE
      )
    }

    # An external link cannot be followed in the current regional table.
    # It is therefore represented as an outlet for regional accumulation.
    downstream_index[
      external_index
    ] <- NA_integer_
  }

  list(
    downstream_index =
      as.integer(
        downstream_index
      ),

    basin_id =
      id_key,

    next_down =
      next_key,

    external_index =
      external_index,

    external_basin_id =
      id_key[external_index],

    external_next_down =
      next_key[external_index],

    n_external =
      length(external_index)
  )
}


accumulate_downstream <- function(
    local_values,
    downstream,
    nonfinite_to_zero = TRUE
) {
  local_values <- as.matrix(
    local_values
  )

  storage.mode(
    local_values
  ) <- "double"

  n <- nrow(
    local_values
  )

  if (
    length(downstream) != n
  ) {
    stop(
      "downstream length must equal the number of matrix rows."
    )
  }

  downstream <- as.integer(
    downstream
  )

  invalid_downstream <- which(
    !is.na(downstream) &
      (
        downstream < 1L |
          downstream > n
      )
  )

  if (length(invalid_downstream) > 0L) {
    stop(
      "Invalid downstream row indices."
    )
  }

  if (nonfinite_to_zero) {
    local_values[
      !is.finite(local_values)
    ] <- 0
  } else if (
    any(
      !is.finite(local_values)
    )
  ) {
    stop(
      "local_values contains non-finite values."
    )
  }

  n_immediate_upstream <- tabulate(
    downstream[
      !is.na(downstream)
    ],
    nbins = n
  )

  initial_queue <- which(
    n_immediate_upstream == 0L
  )

  queue <- integer(n)

  if (length(initial_queue) > 0L) {
    queue[
      seq_along(initial_queue)
    ] <- initial_queue
  }

  queue_position <- 1L
  queue_end <- length(
    initial_queue
  )

  accumulated <- local_values

  n_processed <- 0L

  while (
    queue_position <=
      queue_end
  ) {
    current <- queue[
      queue_position
    ]

    queue_position <-
      queue_position + 1L

    n_processed <-
      n_processed + 1L

    downstream_basin <-
      downstream[current]

    if (!is.na(downstream_basin)) {
      accumulated[
        downstream_basin,
      ] <-
        accumulated[
          downstream_basin,
        ] +
        accumulated[
          current,
        ]

      n_immediate_upstream[
        downstream_basin
      ] <-
        n_immediate_upstream[
          downstream_basin
        ] - 1L

      if (
        n_immediate_upstream[
          downstream_basin
        ] == 0L
      ) {
        queue_end <-
          queue_end + 1L

        queue[
          queue_end
        ] <- downstream_basin
      }
    }
  }

  if (n_processed != n) {
    unresolved <- which(
      n_immediate_upstream > 0L
    )

    stop(
      "Network accumulation processed ",
      n_processed,
      " of ",
      n,
      " basins. Possible cycle. Unresolved rows: ",
      paste(
        head(
          unresolved,
          20
        ),
        collapse = ", "
      )
    )
  }

  accumulated
}


network_has_cycle <- function(
    downstream
) {
  test_values <- matrix(
    1,
    nrow = length(downstream),
    ncol = 1
  )

  tryCatch(
    {
      accumulate_downstream(
        test_values,
        downstream
      )

      FALSE
    },
    error = function(e) {
      grepl(
        "Possible cycle",
        conditionMessage(e),
        fixed = TRUE
      )
    }
  )
}
