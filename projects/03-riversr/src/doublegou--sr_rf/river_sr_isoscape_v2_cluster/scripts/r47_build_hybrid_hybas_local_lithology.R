#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("Package 'data.table' is required.")
  }
})

library(data.table)

options(
  stringsAsFactors = FALSE,
  warn = 1,
  scipen = 999
)

# ==============================================================================
# R47: Build a HYBAS-version-consistent full-range local lithology model table
#
# Core rules:
#   1. Preserve the frozen P0 sample and frozen p0__up_geo_* fields.
#   2. Use current HYBAS assignments by default.
#   3. For exactly 7 known legacy/current mismatch sites, use legacy_HYBAS_ID
#      to extract LOCAL lithology.
#   4. Do not replace frozen P0 upstream lithology with current asset upstream.
#   5. Construct:
#        - 8 local lithology fractions
#        - 8 local-minus-frozen-upstream contrasts
#        - compact radiogenic-source proxy features
#   6. Require:
#        - n = 4485
#        - Sr >= 0.75: n = 109
#        - Sr >= 0.80: n = 20
#        - local lithology complete for all 4485
#        - exactly 7 legacy overrides
#        - current-versus-legacy local comparison reproduces:
#             19 differing site x lithology cells
#             6 distinct affected sites
# ==============================================================================


# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------

PROJECT_ROOT <- normalizePath(
  Sys.getenv("PROJECT_ROOT", unset = getwd()),
  mustWork = TRUE
)

project_path <- function(...) {
  file.path(PROJECT_ROOT, ...)
}

P0_FILE <- project_path(
  "data",
  "processed",
  "model_table_p0_full_range.rds"
)

FOLDS_FILE <- project_path(
  "data",
  "processed",
  "folds_long.rds"
)

ASSIGNMENT_FILE <- project_path(
  "outputs",
  "model_age_join",
  "sample_hydrobasins_l6_assignment.csv"
)

MISMATCH_FILE <- project_path(
  "outputs",
  "full_range_p0_recovery",
  "hybas_7_mismatches.csv"
)

R46_CANDIDATE_FILE <- project_path(
  "outputs",
  "r46_full_range_local_lithology_compatibility",
  "full_range_local_upstream_lithology_candidate.rds"
)

GLIM_DIR <- normalizePath(
  "/home/zhangmeng/projects/sr_global/data_processed/global/glim_l6_by_region",
  mustWork = TRUE
)

OUT_DIR <- project_path(
  "outputs",
  "r47_hybrid_local_lithology"
)

FULL_TABLE_FILE <- project_path(
  "data",
  "processed",
  "model_table_p0_full_range_r47_hybrid_local_lithology.rds"
)

FEATURE_TABLE_FILE <- file.path(
  OUT_DIR,
  "full_range_r47_local_lithology_features.rds"
)

MODULE_RDS_FILE <- file.path(
  OUT_DIR,
  "r47_module_features.rds"
)

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(FULL_TABLE_FILE), recursive = TRUE, showWarnings = FALSE)


# ------------------------------------------------------------------------------
# Expected invariants
# ------------------------------------------------------------------------------

EXPECTED_N_ALL <- 4485L
EXPECTED_N_GE_075 <- 109L
EXPECTED_N_GE_080 <- 20L

EXPECTED_LEGACY_OVERRIDES <- 7L
EXPECTED_CHANGED_SITES <- 6L
EXPECTED_CHANGED_CELLS <- 19L

N_LITHOLOGY_CLASSES <- 8L
DIFF_TOLERANCE <- 1e-10


# ------------------------------------------------------------------------------
# Basic helpers
# ------------------------------------------------------------------------------

assert_file <- function(path) {
  if (!file.exists(path)) {
    stop("Required input does not exist: ", path)
  }
}

for (f in c(
  P0_FILE,
  ASSIGNMENT_FILE,
  MISMATCH_FILE,
  R46_CANDIDATE_FILE
)) {
  assert_file(f)
}

norm_col <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x <- gsub("_+", "_", x)
  x
}

clean_id <- function(x) {
  missing <- is.na(x)

  if (is.numeric(x)) {
    out <- format(
      x,
      scientific = FALSE,
      trim = TRUE,
      digits = 22
    )
  } else {
    out <- trimws(as.character(x))
  }

  out <- sub("\\.0+$", "", out)
  out[out %in% c("", "NA", "NaN", "NULL")] <- NA_character_
  out[missing] <- NA_character_

  out
}

numeric_value <- function(x) {
  if (is.numeric(x)) {
    return(as.numeric(x))
  }

  suppressWarnings(as.numeric(as.character(x)))
}

first_non_missing <- function(x) {
  x <- x[!is.na(x)]

  if (length(x) == 0L) {
    return(NA_real_)
  }

  x[[1L]]
}

numeric_spread <- function(x) {
  x <- numeric_value(x)
  x <- x[is.finite(x)]

  if (length(x) <= 1L) {
    return(0)
  }

  max(x) - min(x)
}

check_unique_mapping <- function(dt, id_col, value_col, label) {
  tmp <- dt[
    !is.na(get(id_col)),
    .(
      n_values = uniqueN(get(value_col)[!is.na(get(value_col))])
    ),
    by = id_col
  ]

  bad <- tmp[n_values > 1L]

  if (nrow(bad) > 0L) {
    stop(
      label,
      " contains conflicting mappings for ",
      nrow(bad),
      " IDs."
    )
  }
}


# ------------------------------------------------------------------------------
# Detect site identifier columns by value overlap
# ------------------------------------------------------------------------------

candidate_id_columns <- function(dt) {
  nms <- names(dt)
  nn <- norm_col(nms)

  positive <- grepl(
    "site|sample|station|record|point|location|loc_id|key|(^|_)id($|_)",
    nn
  )

  negative <- grepl(
    paste(
      c(
        "hybas",
        "hydrobas",
        "basin",
        "region",
        "fold",
        "cluster",
        "country",
        "river",
        "lith",
        "geolog",
        "geo_",
        "feature",
        "row_number"
      ),
      collapse = "|"
    ),
    nn
  )

  nms[positive & !negative]
}

choose_id_pair <- function(dt_a, dt_b, label_a, label_b) {
  cand_a <- candidate_id_columns(dt_a)
  cand_b <- candidate_id_columns(dt_b)

  if (length(cand_a) == 0L || length(cand_b) == 0L) {
    stop(
      "Could not identify candidate site-ID columns in ",
      label_a,
      " and/or ",
      label_b,
      "."
    )
  }

  results <- list()
  k <- 0L

  for (a in cand_a) {
    va <- unique(na.omit(clean_id(dt_a[[a]])))

    for (b in cand_b) {
      vb <- unique(na.omit(clean_id(dt_b[[b]])))

      intersection_n <- length(intersect(va, vb))
      smaller_n <- min(length(va), length(vb))

      coverage <- if (smaller_n > 0L) {
        intersection_n / smaller_n
      } else {
        0
      }

      same_name <- as.integer(norm_col(a) == norm_col(b))

      k <- k + 1L
      results[[k]] <- data.table(
        column_a = a,
        column_b = b,
        intersection_n = intersection_n,
        coverage = coverage,
        same_name = same_name
      )
    }
  }

  scores <- rbindlist(results)

  setorder(
    scores,
    -intersection_n,
    -coverage,
    -same_name,
    column_a,
    column_b
  )

  best <- scores[1L]

  if (best$intersection_n == 0L) {
    stop(
      "No overlapping site identifiers were found between ",
      label_a,
      " and ",
      label_b,
      "."
    )
  }

  best
}

choose_column_by_overlap <- function(
  reference_ids,
  dt,
  label,
  expected_overlap = NULL
) {
  candidates <- candidate_id_columns(dt)

  if (length(candidates) == 0L) {
    stop("No candidate site-ID column found in ", label, ".")
  }

  reference_ids <- unique(na.omit(clean_id(reference_ids)))

  scores <- rbindlist(lapply(candidates, function(col) {
    values <- unique(na.omit(clean_id(dt[[col]])))

    data.table(
      column = col,
      overlap_n = length(intersect(reference_ids, values)),
      candidate_unique_n = length(values)
    )
  }))

  setorder(scores, -overlap_n, candidate_unique_n, column)

  best <- scores[1L]

  if (!is.null(expected_overlap) &&
      best$overlap_n != expected_overlap) {
    stop(
      "Best ID column in ",
      label,
      " has overlap ",
      best$overlap_n,
      "; expected ",
      expected_overlap,
      ". Candidate: ",
      best$column
    )
  }

  best$column
}


# ------------------------------------------------------------------------------
# HYBAS column detection
# ------------------------------------------------------------------------------

detect_hybas_column <- function(
  dt,
  flavour = c("generic", "current", "legacy")
) {
  flavour <- match.arg(flavour)

  nms <- names(dt)
  nn <- norm_col(nms)

  hits <- which(grepl("hybas|hydrobas", nn))

  if (length(hits) == 0L) {
    stop("No HYBAS column found. Columns: ", paste(nms, collapse = ", "))
  }

  if (flavour == "legacy") {
    preferred <- hits[grepl("legacy|old", nn[hits])]

    if (length(preferred) > 0L) {
      return(nms[preferred[1L]])
    }
  }

  if (flavour == "current") {
    preferred <- hits[grepl("current|new", nn[hits])]

    if (length(preferred) > 0L) {
      return(nms[preferred[1L]])
    }

    non_legacy <- hits[!grepl("legacy|old", nn[hits])]

    exact <- non_legacy[
      nn[non_legacy] %in% c(
        "hybas_id",
        "hybas_id_l6",
        "hybas_l6",
        "hydrobasins_id"
      )
    ]

    if (length(exact) > 0L) {
      return(nms[exact[1L]])
    }

    if (length(non_legacy) > 0L) {
      return(nms[non_legacy[1L]])
    }
  }

  exact <- hits[
    nn[hits] %in% c(
      "hybas_id",
      "hybas_id_l6",
      "hybas_l6",
      "hydrobasins_id"
    )
  ]

  if (length(exact) > 0L) {
    return(nms[exact[1L]])
  }

  nms[hits[1L]]
}


# ------------------------------------------------------------------------------
# Detect the measured river-Sr response column
# ------------------------------------------------------------------------------

detect_sr_response_column <- function(dt) {
  nms <- names(dt)
  nn <- norm_col(nms)

  name_candidates <- which(
    grepl("sr", nn) &
      !grepl(
        "p0_|up_geo|lith|geolog|feature|prediction|pred_|residual|fold|sd$|se$",
        nn
      )
  )

  if (length(name_candidates) == 0L) {
    name_candidates <- seq_along(nms)
  }

  score_rows <- lapply(name_candidates, function(i) {
    z <- numeric_value(dt[[i]])
    finite <- z[is.finite(z)]

    if (length(finite) == 0L) {
      return(NULL)
    }

    plausible_fraction <- mean(
      finite >= 0.60 &
        finite <= 1.20
    )

    median_value <- median(finite)

    exact_name_bonus <- if (
      nn[i] %in% c(
        "sr",
        "sr_ratio",
        "sr87_86",
        "sr_87_86",
        "87sr_86sr",
        "87sr_86sr_ratio",
        "measured_sr"
      )
    ) {
      100
    } else if (
      grepl("87.*sr.*86|sr.*ratio|measured.*sr", nn[i])
    ) {
      70
    } else if (grepl("sr", nn[i])) {
      30
    } else {
      0
    }

    data.table(
      column = nms[i],
      score =
        exact_name_bonus +
        50 * plausible_fraction -
        20 * abs(median_value - 0.71),
      plausible_fraction = plausible_fraction,
      median_value = median_value,
      finite_n = length(finite)
    )
  })

  score_rows <- Filter(Negate(is.null), score_rows)

  if (length(score_rows) == 0L) {
    stop("Could not identify a numeric Sr response column.")
  }

  scores <- rbindlist(score_rows)
  scores <- scores[plausible_fraction >= 0.80]

  if (nrow(scores) == 0L) {
    stop("No column has a plausible river 87Sr/86Sr value distribution.")
  }

  setorder(scores, -score, -finite_n)

  scores$column[1L]
}


# ------------------------------------------------------------------------------
# Lithology column detection and class matching
# ------------------------------------------------------------------------------

fraction_quality <- function(x) {
  z <- numeric_value(x)
  z <- z[is.finite(z)]

  if (length(z) == 0L) {
    return(0)
  }

  quality_01 <- mean(z >= -1e-8 & z <= 1 + 1e-8)
  quality_100 <- mean(z >= -1e-6 & z <= 100 + 1e-6)

  max(quality_01, quality_100)
}

detect_fraction_columns <- function(
  dt,
  side = c("local", "upstream"),
  expected_n = N_LITHOLOGY_CLASSES
) {
  side <- match.arg(side)

  nms <- names(dt)
  nn <- norm_col(nms)

  if (side == "local") {
    side_hit <- grepl("(^|_)(local|loc)(_|$)", nn)
  } else {
    side_hit <- grepl(
      "upstream|up_geo|(^|_)up(_|$)",
      nn
    )
  }

  excluded <- grepl(
    paste(
      c(
        "hybas",
        "hydrobas",
        "site",
        "sample",
        "station",
        "record",
        "coverage",
        "covered",
        "valid",
        "missing",
        "elev",
        "slope",
        "relief",
        "rugged",
        "terrain",
        "quantile",
        "mean",
        "median",
        "minimum",
        "maximum",
        "range",
        "count",
        "ncell",
        "npixel",
        "area_total",
        "sum_total",
        "local_minus",
        "contrast",
        "difference"
      ),
      collapse = "|"
    ),
    nn
  )

  quality <- vapply(
    dt,
    fraction_quality,
    numeric(1)
  )

  candidates <- nms[
    side_hit &
      !excluded &
      quality >= 0.95
  ]

  if (length(candidates) > expected_n) {
    stronger <- candidates[
      grepl(
        "glim|lith|geolog|geo|frac|fraction|proportion|prop",
        norm_col(candidates)
      )
    ]

    if (length(stronger) == expected_n) {
      candidates <- stronger
    }
  }

  if (length(candidates) != expected_n) {
    side_names <- nms[side_hit]

    stop(
      "Expected exactly ",
      expected_n,
      " ",
      side,
      " lithology fractions but detected ",
      length(candidates),
      ".\nDetected candidates: ",
      paste(candidates, collapse = ", "),
      "\nAll side-labelled columns: ",
      paste(side_names, collapse = ", ")
    )
  }

  candidates
}

lithology_token <- function(column_name) {
  x <- norm_col(column_name)

  words <- unlist(strsplit(x, "_", fixed = TRUE))

  generic_words <- c(
    "p0",
    "r45",
    "r46",
    "r47",
    "glim",
    "geo",
    "geology",
    "geological",
    "lith",
    "lithology",
    "lithological",
    "fraction",
    "fractions",
    "frac",
    "proportion",
    "prop",
    "local",
    "loc",
    "upstream",
    "up",
    "frozen",
    "current",
    "catchment",
    "basin",
    "asset",
    "class",
    "type"
  )

  words <- words[
    nzchar(words) &
      !words %in% generic_words
  ]

  paste(words, collapse = "_")
}

canonical_lithology_class <- function(column_name) {
  raw <- lithology_token(column_name)
  compact <- gsub("_", "", raw)

  if (raw %in% c("su") ||
      grepl("unconsolid|alluv|loess|surficial|regolith", compact)) {
    return("unconsolidated")
  }

  if (raw %in% c("ss") ||
      grepl("siliciclast|sandstone|mudstone|shale", compact)) {
    return("siliciclastic")
  }

  if (raw %in% c("sm") ||
      grepl("mixedsed|sedmixed|mixedsedimentary", compact)) {
    return("mixed_sedimentary")
  }

  if (raw %in% c("sc") ||
      grepl("carbonate|limestone|dolomite|carbonatic", compact)) {
    return("carbonate")
  }

  if (raw %in% c("py") ||
      grepl("pyroclast|tephra|tuff", compact)) {
    return("pyroclastic")
  }

  if (raw %in% c("va") ||
      grepl(
        "acidvolcan|felsicvolcan|rhyolit|dacitic",
        compact
      )) {
    return("acid_volcanic")
  }

  if (raw %in% c("vi") ||
      grepl("intermediatevolcan|andesit", compact)) {
    return("intermediate_volcanic")
  }

  if (raw %in% c("vb") ||
      grepl("basicvolcan|maficvolcan|basalt", compact)) {
    return("basic_volcanic")
  }

  if (grepl("volcan|extrusive", compact)) {
    return("volcanic")
  }

  if (raw %in% c("pa") ||
      grepl(
        "acidpluton|felsicpluton|granit|granodior",
        compact
      )) {
    return("acid_plutonic")
  }

  if (raw %in% c("pi") ||
      grepl("intermediatepluton|diorit", compact)) {
    return("intermediate_plutonic")
  }

  if (raw %in% c("pb") ||
      grepl("basicpluton|maficpluton|gabbro", compact)) {
    return("basic_plutonic")
  }

  if (grepl("pluton|intrusive", compact)) {
    return("plutonic")
  }

  if (raw %in% c("mt") ||
      grepl(
        "metamorph|gneiss|schist|quartzite",
        compact
      )) {
    return("metamorphic")
  }

  if (raw %in% c("wb") ||
      grepl("waterbody|surfacewater|lake|ocean", compact)) {
    return("water")
  }

  if (raw %in% c("ig") ||
      grepl("ice|glacier", compact)) {
    return("ice")
  }

  if (raw %in% c("no", "na", "nodata") ||
      grepl("nodata|unknown|unclassified", compact)) {
    return("unclassified")
  }

  raw
}

infer_fraction_denominator <- function(dt, columns, label) {
  mat <- as.matrix(
    dt[, ..columns]
  )

  storage.mode(mat) <- "numeric"

  complete <- complete.cases(mat)

  if (!any(complete)) {
    stop("No complete rows available to infer fraction scale for ", label, ".")
  }

  sums <- rowSums(
    mat[complete, , drop = FALSE]
  )

  median_sum <- median(
    sums[is.finite(sums)],
    na.rm = TRUE
  )

  if (median_sum >= 0.30 && median_sum <= 1.50) {
    return(1)
  }

  if (median_sum >= 30 && median_sum <= 150) {
    return(100)
  }

  stop(
    "Could not infer fraction denominator for ",
    label,
    ". Median complete-row sum = ",
    signif(median_sum, 8)
  )
}


# ------------------------------------------------------------------------------
# Extract tabular objects from GLiM RDS files
# ------------------------------------------------------------------------------

collect_data_frames <- function(
  object,
  prefix = "root",
  depth = 0L,
  max_depth = 5L
) {
  if (depth > max_depth) {
    return(list())
  }

  if (is.data.frame(object)) {
    out <- list(object)
    names(out) <- prefix
    return(out)
  }

  if (!is.list(object)) {
    return(list())
  }

  output <- list()

  object_names <- names(object)

  if (is.null(object_names)) {
    object_names <- as.character(seq_along(object))
  }

  for (i in seq_along(object)) {
    child_prefix <- paste0(
      prefix,
      "$",
      object_names[i]
    )

    output <- c(
      output,
      collect_data_frames(
        object[[i]],
        prefix = child_prefix,
        depth = depth + 1L,
        max_depth = max_depth
      )
    )
  }

  output
}

extract_asset_table <- function(path) {
  object <- readRDS(path)

  tables <- collect_data_frames(object)

  if (length(tables) == 0L) {
    stop("No data.frame-like object found in asset: ", path)
  }

  has_hybas <- vapply(
    tables,
    function(tab) {
      !is.null(
        tryCatch(
          detect_hybas_column(tab),
          error = function(e) NULL
        )
      )
    },
    logical(1)
  )

  tables <- tables[has_hybas]

  if (length(tables) == 0L) {
    stop("No HYBAS-indexed table found in asset: ", path)
  }

  sizes <- vapply(
    tables,
    nrow,
    integer(1)
  )

  selected_name <- names(tables)[which.max(sizes)]
  selected <- as.data.table(tables[[selected_name]])

  list(
    table = selected,
    component = selected_name
  )
}


# ------------------------------------------------------------------------------
# Read core inputs
# ------------------------------------------------------------------------------

message("Reading P0 table: ", P0_FILE)
p0 <- as.data.table(readRDS(P0_FILE))

message("Reading R46 candidate schema: ", R46_CANDIDATE_FILE)
r46_candidate <- as.data.table(readRDS(R46_CANDIDATE_FILE))

message("Reading current HYBAS assignments: ", ASSIGNMENT_FILE)
assignment <- fread(
  ASSIGNMENT_FILE,
  colClasses = "character",
  na.strings = c("", "NA", "NaN", "NULL")
)

message("Reading known HYBAS mismatch table: ", MISMATCH_FILE)
mismatch <- fread(
  MISMATCH_FILE,
  colClasses = "character",
  na.strings = c("", "NA", "NaN", "NULL")
)

message(
  "Defining the frozen 4485-site P0 sample using complete P0 baseline fields."
)

# model_table_p0_full_range.rds contains 4527 candidate rows.
# The frozen M0_P0_FULL modelling sample consists of rows complete across
# the existing p0__ baseline fields. Exactly 42 rows are excluded.
#
# This operation defines sample membership only:
#   - local lithology is subsequently joined using hybrid HYBAS;
#   - frozen p0__up_geo_* fields remain the upstream lithology source.

p0_raw_n <- nrow(p0)

p0_baseline_columns <- grep(
  "^p0__",
  names(p0),
  value = TRUE
)

if (length(p0_baseline_columns) == 0L) {
  stop("No baseline fields matching '^p0__' were found.")
}

p0_scope_site_column <- if ("row_id" %in% names(p0)) {
  "row_id"
} else {
  candidates <- candidate_id_columns(p0)

  if (length(candidates) == 0L) {
    stop("No site identifier is available for the P0 scope audit.")
  }

  candidates[1L]
}

p0_scope_ids <- clean_id(
  p0[[p0_scope_site_column]]
)

if (anyNA(p0_scope_ids)) {
  stop(
    "P0 scope identifier contains ",
    sum(is.na(p0_scope_ids)),
    " missing values. Column: ",
    p0_scope_site_column
  )
}

if (anyDuplicated(p0_scope_ids)) {
  stop(
    "P0 scope identifier is not unique. Column: ",
    p0_scope_site_column
  )
}

p0_missing_field_count <- rowSums(
  is.na(
    p0[, ..p0_baseline_columns]
  )
)

in_frozen_p0_sample <- complete.cases(
  p0[, ..p0_baseline_columns]
)

if (sum(in_frozen_p0_sample) != EXPECTED_N_ALL) {
  missing_distribution <- paste(
    names(table(p0_missing_field_count)),
    as.integer(table(p0_missing_field_count)),
    sep = ":",
    collapse = "; "
  )

  stop(
    "Complete cases across ",
    length(p0_baseline_columns),
    " p0__ fields produced ",
    sum(in_frozen_p0_sample),
    " rows; expected ",
    EXPECTED_N_ALL,
    ". Missing-field distribution: ",
    missing_distribution
  )
}

if (sum(!in_frozen_p0_sample) != 42L) {
  stop(
    "Expected exactly 42 incomplete P0 rows but found ",
    sum(!in_frozen_p0_sample),
    "."
  )
}

p0_scope_audit <- data.table(
  site_id = p0_scope_ids,
  in_frozen_p0_sample = in_frozen_p0_sample,
  n_missing_p0_fields = p0_missing_field_count,
  sample_scope_source =
    "complete_cases_across_all_p0_prefixed_fields"
)

fwrite(
  p0_scope_audit,
  file.path(
    OUT_DIR,
    "p0_sample_scope_audit.csv"
  )
)

fwrite(
  p0_scope_audit[
    in_frozen_p0_sample == FALSE
  ],
  file.path(
    OUT_DIR,
    "p0_excluded_incomplete_rows.csv"
  )
)

p0 <- p0[in_frozen_p0_sample]

if (nrow(p0) != EXPECTED_N_ALL) {
  stop(
    "After P0 complete-case filtering, table contains ",
    nrow(p0),
    " rows; expected ",
    EXPECTED_N_ALL,
    "."
  )
}

message(
  "P0 sample scope: retained ",
  nrow(p0),
  " of ",
  p0_raw_n,
  " rows using complete cases across ",
  length(p0_baseline_columns),
  " p0__ fields; excluded ",
  p0_raw_n - nrow(p0),
  "."
)


# ------------------------------------------------------------------------------
# Resolve the eight local classes and eight frozen upstream classes
# ------------------------------------------------------------------------------

local_source_columns <- detect_fraction_columns(
  r46_candidate,
  side = "local"
)

local_classes <- vapply(
  local_source_columns,
  canonical_lithology_class,
  character(1)
)

if (anyDuplicated(local_classes)) {
  stop(
    "Local lithology classes are not uniquely identified:\n",
    paste(
      local_source_columns,
      "=>",
      local_classes,
      collapse = "\n"
    )
  )
}

frozen_upstream_columns <- grep(
  "^p0__up_geo_",
  names(p0),
  value = TRUE
)

if (length(frozen_upstream_columns) != N_LITHOLOGY_CLASSES) {
  stop(
    "Expected exactly 8 frozen P0 upstream fields matching ",
    "'^p0__up_geo_' but found ",
    length(frozen_upstream_columns),
    ":\n",
    paste(frozen_upstream_columns, collapse = ", ")
  )
}

upstream_classes <- vapply(
  frozen_upstream_columns,
  canonical_lithology_class,
  character(1)
)

if (anyDuplicated(upstream_classes)) {
  stop(
    "Frozen upstream classes are not uniquely identified:\n",
    paste(
      frozen_upstream_columns,
      "=>",
      upstream_classes,
      collapse = "\n"
    )
  )
}

preflight_class_mapping <- rbindlist(
  list(
    data.table(
      side = "local_R46_schema",
      source_column = local_source_columns,
      lithology_class = local_classes
    ),
    data.table(
      side = "frozen_P0_upstream",
      source_column = frozen_upstream_columns,
      lithology_class = upstream_classes
    )
  )
)

fwrite(
  preflight_class_mapping,
  file.path(
    OUT_DIR,
    "preflight_lithology_class_mapping.csv"
  )
)

if (!setequal(local_classes, upstream_classes)) {
  stop(
    "Local and frozen-upstream lithology classes do not form an exact ",
    "one-to-one set.\nLocal classes: ",
    paste(local_classes, collapse = ", "),
    "\nFrozen upstream classes: ",
    paste(upstream_classes, collapse = ", "),
    "\nSee preflight_lithology_class_mapping.csv"
  )
}

class_order <- local_classes

local_source_by_class <- setNames(
  local_source_columns,
  local_classes
)[class_order]

upstream_source_by_class <- setNames(
  frozen_upstream_columns,
  upstream_classes
)[class_order]

local_denominator <- infer_fraction_denominator(
  r46_candidate,
  unname(local_source_by_class),
  "R46 local lithology"
)

upstream_denominator <- infer_fraction_denominator(
  p0,
  unname(upstream_source_by_class),
  "frozen P0 upstream lithology"
)

local_to_upstream_scale_factor <-
  upstream_denominator / local_denominator

fraction_scale_audit <- data.table(
  object = c(
    "R46/local GLiM asset",
    "frozen P0 upstream"
  ),
  inferred_denominator = c(
    local_denominator,
    upstream_denominator
  ),
  local_to_upstream_scale_factor = c(
    local_to_upstream_scale_factor,
    NA_real_
  )
)

fwrite(
  fraction_scale_audit,
  file.path(
    OUT_DIR,
    "fraction_scale_audit.csv"
  )
)


# ------------------------------------------------------------------------------
# Read and standardise all nine regional GLiM assets
# ------------------------------------------------------------------------------

glim_files <- sort(
  list.files(
    GLIM_DIR,
    pattern = "^l6_glim_local_upstream_.*\\.rds$",
    full.names = TRUE
  )
)

if (length(glim_files) != 9L) {
  stop(
    "Expected 9 regional GLiM assets but found ",
    length(glim_files),
    " in ",
    GLIM_DIR,
    "."
  )
}

standardise_asset <- function(path) {
  extracted <- extract_asset_table(path)
  tab <- extracted$table

  hybas_col <- detect_hybas_column(tab)

  candidate_norm <- norm_col(
    unname(local_source_by_class)
  )

  tab_norm <- norm_col(names(tab))

  exact_indices <- match(
    candidate_norm,
    tab_norm
  )

  if (!anyNA(exact_indices)) {
    asset_local_columns <- names(tab)[exact_indices]
    asset_classes <- class_order
  } else {
    asset_local_columns <- detect_fraction_columns(
      tab,
      side = "local"
    )

    asset_classes <- vapply(
      asset_local_columns,
      canonical_lithology_class,
      character(1)
    )

    if (anyDuplicated(asset_classes)) {
      stop(
        "Asset has non-unique local lithology classes: ",
        basename(path),
        "\n",
        paste(
          asset_local_columns,
          "=>",
          asset_classes,
          collapse = "\n"
        )
      )
    }

    if (!setequal(asset_classes, class_order)) {
      stop(
        "Asset classes differ from R46/P0 class set: ",
        basename(path),
        "\nAsset classes: ",
        paste(asset_classes, collapse = ", "),
        "\nRequired classes: ",
        paste(class_order, collapse = ", ")
      )
    }
  }

  source_by_class <- setNames(
    asset_local_columns,
    asset_classes
  )[class_order]

  output <- data.table(
    hybas_id = clean_id(tab[[hybas_col]])
  )

  for (class_name in class_order) {
    source_col <- source_by_class[[class_name]]

    output[
      ,
      (class_name) :=
        numeric_value(tab[[source_col]]) *
        local_to_upstream_scale_factor
    ]
  }

  output <- output[!is.na(hybas_id)]

  inventory <- data.table(
    asset_file = basename(path),
    selected_component = extracted$component,
    hybas_column = hybas_col,
    n_rows = nrow(tab),
    n_nonmissing_hybas = sum(!is.na(clean_id(tab[[hybas_col]]))),
    n_unique_hybas = uniqueN(output$hybas_id),
    local_source_columns = paste(
      unname(source_by_class),
      collapse = ";"
    ),
    canonical_classes = paste(
      class_order,
      collapse = ";"
    )
  )

  list(
    data = output,
    inventory = inventory
  )
}

message("Reading and standardising 9 regional GLiM assets...")

asset_results <- lapply(
  glim_files,
  standardise_asset
)

asset_inventory <- rbindlist(
  lapply(
    asset_results,
    `[[`,
    "inventory"
  ),
  fill = TRUE
)

fwrite(
  asset_inventory,
  file.path(
    OUT_DIR,
    "glim_asset_inventory.csv"
  )
)

asset_all <- rbindlist(
  lapply(
    asset_results,
    `[[`,
    "data"
  ),
  use.names = TRUE,
  fill = TRUE
)

if (nrow(asset_all) == 0L) {
  stop("The combined GLiM lookup is empty.")
}

duplicate_ids <- asset_all[
  ,
  .N,
  by = hybas_id
][N > 1L]

if (nrow(duplicate_ids) > 0L) {
  duplicate_spread <- asset_all[
    hybas_id %in% duplicate_ids$hybas_id,
    lapply(.SD, numeric_spread),
    by = hybas_id,
    .SDcols = class_order
  ]

  duplicate_spread_long <- melt(
    duplicate_spread,
    id.vars = "hybas_id",
    variable.name = "lithology_class",
    value.name = "spread"
  )

  conflicting_duplicates <- duplicate_spread_long[
    spread > DIFF_TOLERANCE
  ]

  fwrite(
    duplicate_spread_long,
    file.path(
      OUT_DIR,
      "duplicate_hybas_spread_audit.csv"
    )
  )

  if (nrow(conflicting_duplicates) > 0L) {
    stop(
      "Regional GLiM files contain conflicting duplicate HYBAS records. ",
      "See duplicate_hybas_spread_audit.csv"
    )
  }
}

asset_lookup <- asset_all[
  ,
  lapply(.SD, first_non_missing),
  by = hybas_id,
  .SDcols = class_order
]

if (anyDuplicated(asset_lookup$hybas_id)) {
  stop("Internal error: GLiM lookup remains duplicated after consolidation.")
}


# ------------------------------------------------------------------------------
# Resolve site keys and current/legacy HYBAS mappings
# ------------------------------------------------------------------------------

p0_assignment_id_pair <- choose_id_pair(
  p0,
  assignment,
  "P0",
  "current HYBAS assignment"
)

p0_site_column <- p0_assignment_id_pair$column_a
assignment_site_column <- p0_assignment_id_pair$column_b

p0_site_id <- clean_id(
  p0[[p0_site_column]]
)

if (anyNA(p0_site_id)) {
  stop(
    "P0 site identifier contains ",
    sum(is.na(p0_site_id)),
    " missing values. Column: ",
    p0_site_column
  )
}

if (anyDuplicated(p0_site_id)) {
  stop(
    "P0 site identifier is not unique. Column: ",
    p0_site_column
  )
}

if (p0_assignment_id_pair$intersection_n != EXPECTED_N_ALL) {
  stop(
    "P0/current-assignment site overlap is ",
    p0_assignment_id_pair$intersection_n,
    "; expected ",
    EXPECTED_N_ALL,
    ". P0 column: ",
    p0_site_column,
    "; assignment column: ",
    assignment_site_column
  )
}

assignment_hybas_column <- detect_hybas_column(
  assignment,
  flavour = "current"
)

assignment_map <- data.table(
  site_id = clean_id(
    assignment[[assignment_site_column]]
  ),
  current_hybas_id = clean_id(
    assignment[[assignment_hybas_column]]
  )
)

assignment_map <- assignment_map[
  !is.na(site_id)
]

check_unique_mapping(
  assignment_map,
  "site_id",
  "current_hybas_id",
  "Current HYBAS assignment"
)

assignment_map <- unique(
  assignment_map,
  by = "site_id"
)

assignment_index <- match(
  p0_site_id,
  assignment_map$site_id
)

if (anyNA(assignment_index)) {
  stop(
    sum(is.na(assignment_index)),
    " P0 sites have no current HYBAS assignment."
  )
}

current_hybas_id <- assignment_map$current_hybas_id[
  assignment_index
]

if (anyNA(current_hybas_id)) {
  stop(
    sum(is.na(current_hybas_id)),
    " P0 sites have missing current HYBAS IDs."
  )
}

mismatch_site_column <- choose_column_by_overlap(
  p0_site_id,
  mismatch,
  "known mismatch table",
  expected_overlap = EXPECTED_LEGACY_OVERRIDES
)

legacy_hybas_column <- detect_hybas_column(
  mismatch,
  flavour = "legacy"
)

mismatch_current_hybas_column <- detect_hybas_column(
  mismatch,
  flavour = "current"
)

mismatch_map <- data.table(
  site_id = clean_id(
    mismatch[[mismatch_site_column]]
  ),
  legacy_hybas_id = clean_id(
    mismatch[[legacy_hybas_column]]
  ),
  mismatch_current_hybas_id = clean_id(
    mismatch[[mismatch_current_hybas_column]]
  )
)

mismatch_map <- mismatch_map[
  !is.na(site_id)
]

mismatch_conflict <- mismatch_map[
  ,
  .(
    n_legacy = uniqueN(
      legacy_hybas_id[!is.na(legacy_hybas_id)]
    ),
    n_current = uniqueN(
      mismatch_current_hybas_id[
        !is.na(mismatch_current_hybas_id)
      ]
    )
  ),
  by = site_id
][n_legacy > 1L | n_current > 1L]

if (nrow(mismatch_conflict) > 0L) {
  stop("Mismatch file contains conflicting rows for one or more sites.")
}

mismatch_map <- unique(
  mismatch_map,
  by = "site_id"
)

if (nrow(mismatch_map) != EXPECTED_LEGACY_OVERRIDES) {
  stop(
    "Mismatch table has ",
    nrow(mismatch_map),
    " unique sites; expected ",
    EXPECTED_LEGACY_OVERRIDES,
    "."
  )
}

if (anyNA(mismatch_map$legacy_hybas_id) ||
    anyNA(mismatch_map$mismatch_current_hybas_id)) {
  stop("Mismatch table contains missing legacy/current HYBAS IDs.")
}

mismatch_index <- match(
  p0_site_id,
  mismatch_map$site_id
)

use_legacy <- !is.na(mismatch_index)

if (sum(use_legacy) != EXPECTED_LEGACY_OVERRIDES) {
  stop(
    "Legacy override count is ",
    sum(use_legacy),
    "; expected ",
    EXPECTED_LEGACY_OVERRIDES,
    "."
  )
}

mismatch_current_for_p0 <- rep(
  NA_character_,
  nrow(p0)
)

legacy_hybas_for_p0 <- rep(
  NA_character_,
  nrow(p0)
)

mismatch_current_for_p0[use_legacy] <-
  mismatch_map$mismatch_current_hybas_id[
    mismatch_index[use_legacy]
  ]

legacy_hybas_for_p0[use_legacy] <-
  mismatch_map$legacy_hybas_id[
    mismatch_index[use_legacy]
  ]

current_disagreement <- use_legacy &
  current_hybas_id != mismatch_current_for_p0

if (any(current_disagreement)) {
  stop(
    "Current assignment disagrees with mismatch-file current_HYBAS_ID ",
    "for ",
    sum(current_disagreement),
    " legacy sites."
  )
}

hybrid_hybas_id <- current_hybas_id
hybrid_hybas_id[use_legacy] <-
  legacy_hybas_for_p0[use_legacy]

hybas_source <- ifelse(
  use_legacy,
  "legacy_override",
  "current_assignment"
)


# ------------------------------------------------------------------------------
# Identify Sr column and reproduce frozen full-range counts
# ------------------------------------------------------------------------------

sr_column <- detect_sr_response_column(p0)
sr_value <- numeric_value(p0[[sr_column]])

if (anyNA(sr_value)) {
  stop(
    "Detected Sr response column contains ",
    sum(is.na(sr_value)),
    " missing values: ",
    sr_column
  )
}

n_ge_075 <- sum(sr_value >= 0.75)
n_ge_080 <- sum(sr_value >= 0.80)

if (n_ge_075 != EXPECTED_N_GE_075) {
  stop(
    "Detected ",
    n_ge_075,
    " sites with Sr >= 0.75; expected ",
    EXPECTED_N_GE_075,
    ". Detected response column: ",
    sr_column
  )
}

if (n_ge_080 != EXPECTED_N_GE_080) {
  stop(
    "Detected ",
    n_ge_080,
    " sites with Sr >= 0.80; expected ",
    EXPECTED_N_GE_080,
    ". Detected response column: ",
    sr_column
  )
}

if (sum(use_legacy & sr_value >= 0.75) != 0L) {
  stop("At least one legacy-override site has Sr >= 0.75; expected zero.")
}

if (sum(use_legacy & sr_value >= 0.80) != 0L) {
  stop("At least one legacy-override site has Sr >= 0.80; expected zero.")
}


# ------------------------------------------------------------------------------
# Reproduce the known current-versus-legacy lithology discrepancy
# ------------------------------------------------------------------------------

mismatch_current_lookup_index <- match(
  mismatch_map$mismatch_current_hybas_id,
  asset_lookup$hybas_id
)

mismatch_legacy_lookup_index <- match(
  mismatch_map$legacy_hybas_id,
  asset_lookup$hybas_id
)

if (anyNA(mismatch_current_lookup_index)) {
  stop(
    "Missing current local lithology for ",
    sum(is.na(mismatch_current_lookup_index)),
    " mismatch HYBAS IDs."
  )
}

if (anyNA(mismatch_legacy_lookup_index)) {
  stop(
    "Missing legacy local lithology for ",
    sum(is.na(mismatch_legacy_lookup_index)),
    " mismatch HYBAS IDs."
  )
}

current_local_matrix <- as.matrix(
  asset_lookup[
    mismatch_current_lookup_index,
    ..class_order
  ]
)

legacy_local_matrix <- as.matrix(
  asset_lookup[
    mismatch_legacy_lookup_index,
    ..class_order
  ]
)

storage.mode(current_local_matrix) <- "numeric"
storage.mode(legacy_local_matrix) <- "numeric"

difference_matrix <- abs(
  current_local_matrix -
    legacy_local_matrix
) > DIFF_TOLERANCE

changed_cells_n <- sum(
  difference_matrix,
  na.rm = TRUE
)

changed_sites_n <- sum(
  rowSums(
    difference_matrix,
    na.rm = TRUE
  ) > 0L
)

if (changed_cells_n != EXPECTED_CHANGED_CELLS) {
  stop(
    "Current-versus-legacy audit reproduced ",
    changed_cells_n,
    " differing site x lithology cells; expected ",
    EXPECTED_CHANGED_CELLS,
    "."
  )
}

if (changed_sites_n != EXPECTED_CHANGED_SITES) {
  stop(
    "Current-versus-legacy audit reproduced ",
    changed_sites_n,
    " changed sites; expected ",
    EXPECTED_CHANGED_SITES,
    "."
  )
}

legacy_comparison <- copy(mismatch_map)

for (j in seq_along(class_order)) {
  class_name <- class_order[j]

  legacy_comparison[
    ,
    paste0("current__", class_name) :=
      current_local_matrix[, j]
  ]

  legacy_comparison[
    ,
    paste0("legacy__", class_name) :=
      legacy_local_matrix[, j]
  ]

  legacy_comparison[
    ,
    paste0("different__", class_name) :=
      difference_matrix[, j]
  ]
}

legacy_comparison[
  ,
  n_different_classes :=
    rowSums(difference_matrix, na.rm = TRUE)
]

legacy_comparison[
  ,
  any_lithology_difference :=
    n_different_classes > 0L
]

fwrite(
  legacy_comparison,
  file.path(
    OUT_DIR,
    "legacy_current_local_lithology_comparison.csv"
  )
)


# ------------------------------------------------------------------------------
# Join hybrid local lithology to the frozen P0 table
# ------------------------------------------------------------------------------

hybrid_lookup_index <- match(
  hybrid_hybas_id,
  asset_lookup$hybas_id
)

if (anyNA(hybrid_lookup_index)) {
  stop(
    sum(is.na(hybrid_lookup_index)),
    " P0 sites have no local lithology for their hybrid HYBAS ID."
  )
}

reserved_audit_columns <- c(
  "r47__current_hybas_id",
  "r47__legacy_hybas_id",
  "r47__hybrid_hybas_id",
  "r47__hybas_source"
)

if (any(reserved_audit_columns %in% names(p0))) {
  stop(
    "R47 audit columns already exist in P0 table: ",
    paste(
      intersect(reserved_audit_columns, names(p0)),
      collapse = ", "
    )
  )
}

p0[
  ,
  r47__current_hybas_id :=
    current_hybas_id
]

p0[
  ,
  r47__legacy_hybas_id :=
    legacy_hybas_for_p0
]

p0[
  ,
  r47__hybrid_hybas_id :=
    hybrid_hybas_id
]

p0[
  ,
  r47__hybas_source :=
    hybas_source
]

local_feature_names <- setNames(
  paste0(
    "r47__local_geo_",
    class_order
  ),
  class_order
)

contrast_feature_names <- setNames(
  paste0(
    "r47__local_minus_up_geo_",
    class_order
  ),
  class_order
)

if (any(c(
  unname(local_feature_names),
  unname(contrast_feature_names)
) %in% names(p0))) {
  stop("One or more planned R47 feature names already exist in P0.")
}

for (class_name in class_order) {
  local_feature <- local_feature_names[[class_name]]
  contrast_feature <- contrast_feature_names[[class_name]]
  upstream_feature <- upstream_source_by_class[[class_name]]

  local_values <- asset_lookup[[class_name]][hybrid_lookup_index]

  upstream_values <- numeric_value(
    p0[[upstream_feature]]
  )

  p0[
    ,
    (local_feature) :=
      local_values
  ]

  p0[
    ,
    (contrast_feature) :=
      local_values - upstream_values
  ]
}


# ------------------------------------------------------------------------------
# Compact radiogenic-source proxy module
# ------------------------------------------------------------------------------

radiogenic_crystalline_classes <- class_order[
  grepl(
    paste(
      c(
        "acid_plutonic",
        "acid_volcanic",
        "metamorphic",
        "felsic",
        "granite",
        "gneiss"
      ),
      collapse = "|"
    ),
    class_order
  )
]

if (length(radiogenic_crystalline_classes) == 0L) {
  radiogenic_crystalline_classes <- class_order[
    grepl(
      "plutonic|metamorphic",
      class_order
    )
  ]
}

siliciclastic_classes <- class_order[
  grepl(
    "siliciclastic",
    class_order
  )
]

radiogenic_groups <- list()

if (length(radiogenic_crystalline_classes) > 0L) {
  radiogenic_groups[["radiogenic_crystalline"]] <-
    radiogenic_crystalline_classes
}

if (length(siliciclastic_classes) > 0L) {
  radiogenic_groups[["siliciclastic_source"]] <-
    siliciclastic_classes
}

if (length(radiogenic_groups) == 0L) {
  stop(
    "No theoretically interpretable radiogenic-source group could be ",
    "identified from the eight classes: ",
    paste(class_order, collapse = ", ")
  )
}

radiogenic_feature_names <- character()
radiogenic_rule_rows <- list()
rule_i <- 0L

for (group_name in names(radiogenic_groups)) {
  group_classes <- radiogenic_groups[[group_name]]

  group_local_columns <- unname(
    local_feature_names[group_classes]
  )

  group_contrast_columns <- unname(
    contrast_feature_names[group_classes]
  )

  local_proxy_name <- paste0(
    "r47__local_",
    group_name,
    "_proxy"
  )

  contrast_proxy_name <- paste0(
    "r47__contrast_",
    group_name,
    "_proxy"
  )

  p0[
    ,
    (local_proxy_name) :=
      rowSums(
        as.matrix(.SD),
        na.rm = FALSE
      ),
    .SDcols = group_local_columns
  ]

  p0[
    ,
    (contrast_proxy_name) :=
      rowSums(
        as.matrix(.SD),
        na.rm = FALSE
      ),
    .SDcols = group_contrast_columns
  ]

  radiogenic_feature_names <- c(
    radiogenic_feature_names,
    local_proxy_name,
    contrast_proxy_name
  )

  for (class_name in group_classes) {
    rule_i <- rule_i + 1L

    rationale <- if (
      group_name == "radiogenic_crystalline"
    ) {
      paste(
        "Broad proxy for old/felsic crystalline or metamorphic",
        "source material with potential for elevated radiogenic Sr;",
        "not interpreted as a deterministic Sr-ratio class."
      )
    } else {
      paste(
        "Siliciclastic source proxy, potentially integrating weathered",
        "continental material; retained separately from crystalline sources."
      )
    }

    radiogenic_rule_rows[[rule_i]] <- data.table(
      proxy_group = group_name,
      lithology_class = class_name,
      local_component = local_feature_names[[class_name]],
      contrast_component = contrast_feature_names[[class_name]],
      rationale = rationale
    )
  }
}

radiogenic_rule <- rbindlist(
  radiogenic_rule_rows,
  fill = TRUE
)

fwrite(
  radiogenic_rule,
  file.path(
    OUT_DIR,
    "radiogenic_compact_rule.csv"
  )
)


# ------------------------------------------------------------------------------
# Completeness and coverage audit
# ------------------------------------------------------------------------------

local_matrix <- as.matrix(
  p0[
    ,
    ..local_feature_names
  ]
)

upstream_matrix <- as.matrix(
  p0[
    ,
    ..upstream_source_by_class
  ]
)

contrast_matrix <- as.matrix(
  p0[
    ,
    ..contrast_feature_names
  ]
)

storage.mode(local_matrix) <- "numeric"
storage.mode(upstream_matrix) <- "numeric"
storage.mode(contrast_matrix) <- "numeric"

local_complete <- complete.cases(local_matrix)
upstream_complete <- complete.cases(upstream_matrix)
contrast_complete <- complete.cases(contrast_matrix)

local_sum <- rowSums(
  local_matrix,
  na.rm = FALSE
)

upstream_sum <- rowSums(
  upstream_matrix,
  na.rm = FALSE
)

coverage_masks <- list(
  full_p0 = rep(TRUE, nrow(p0)),
  sr_ge_075 = sr_value >= 0.75,
  sr_ge_080 = sr_value >= 0.80
)

expected_counts <- c(
  full_p0 = EXPECTED_N_ALL,
  sr_ge_075 = EXPECTED_N_GE_075,
  sr_ge_080 = EXPECTED_N_GE_080
)

coverage_audit <- rbindlist(
  lapply(names(coverage_masks), function(group_name) {
    mask <- coverage_masks[[group_name]]

    data.table(
      subset = group_name,
      expected_n = expected_counts[[group_name]],
      observed_n = sum(mask),
      local_complete_n = sum(local_complete[mask]),
      frozen_upstream_complete_n = sum(upstream_complete[mask]),
      contrast_complete_n = sum(contrast_complete[mask]),
      legacy_override_n = sum(use_legacy[mask]),
      local_sum_min = min(local_sum[mask], na.rm = TRUE),
      local_sum_median = median(local_sum[mask], na.rm = TRUE),
      local_sum_max = max(local_sum[mask], na.rm = TRUE),
      frozen_upstream_sum_min = min(
        upstream_sum[mask],
        na.rm = TRUE
      ),
      frozen_upstream_sum_median = median(
        upstream_sum[mask],
        na.rm = TRUE
      ),
      frozen_upstream_sum_max = max(
        upstream_sum[mask],
        na.rm = TRUE
      )
    )
  })
)

coverage_audit[
  ,
  pass :=
    observed_n == expected_n &
    local_complete_n == observed_n &
    frozen_upstream_complete_n == observed_n &
    contrast_complete_n == observed_n
]

fwrite(
  coverage_audit,
  file.path(
    OUT_DIR,
    "coverage_audit.csv"
  )
)

if (!all(coverage_audit$pass)) {
  stop(
    "One or more R47 coverage checks failed. See coverage_audit.csv"
  )
}

if (sum(local_complete) != EXPECTED_N_ALL) {
  stop(
    "Local lithology is complete for ",
    sum(local_complete),
    " rows; expected ",
    EXPECTED_N_ALL,
    "."
  )
}

if (sum(upstream_complete) != EXPECTED_N_ALL) {
  stop(
    "Frozen upstream lithology is complete for ",
    sum(upstream_complete),
    " rows; expected ",
    EXPECTED_N_ALL,
    "."
  )
}

if (sum(contrast_complete) != EXPECTED_N_ALL) {
  stop(
    "Lithology contrasts are complete for ",
    sum(contrast_complete),
    " rows; expected ",
    EXPECTED_N_ALL,
    "."
  )
}


# ------------------------------------------------------------------------------
# HYBAS join audit
# ------------------------------------------------------------------------------

hybas_join_audit <- data.table(
  site_id = p0_site_id,
  sr_value = sr_value,
  current_hybas_id = current_hybas_id,
  mismatch_file_current_hybas_id =
    mismatch_current_for_p0,
  legacy_hybas_id = legacy_hybas_for_p0,
  hybrid_hybas_id = hybrid_hybas_id,
  hybas_source = hybas_source,
  local_lookup_matched = !is.na(hybrid_lookup_index),
  local_complete = local_complete,
  frozen_upstream_complete = upstream_complete,
  contrast_complete = contrast_complete,
  sr_ge_072 = sr_value >= 0.72,
  sr_ge_075 = sr_value >= 0.75,
  sr_ge_080 = sr_value >= 0.80
)

fwrite(
  hybas_join_audit,
  file.path(
    OUT_DIR,
    "hybas_join_audit.csv"
  )
)

fwrite(
  hybas_join_audit[
    hybas_source == "legacy_override"
  ],
  file.path(
    OUT_DIR,
    "legacy_override_site_audit.csv"
  )
)


# ------------------------------------------------------------------------------
# Feature manifests and R48-ready module definitions
# ------------------------------------------------------------------------------

local_manifest <- data.table(
  module = "M1B_LOCAL",
  feature = unname(local_feature_names),
  feature_type = "local_fraction",
  lithology_class = class_order,
  local_source = unname(local_source_by_class),
  frozen_upstream_source = NA_character_,
  formula = paste0(
    "GLiM local fraction for hybrid HYBAS: ",
    class_order
  )
)

contrast_manifest <- data.table(
  module = "M1B_CONTRAST",
  feature = unname(contrast_feature_names),
  feature_type = "local_minus_frozen_upstream",
  lithology_class = class_order,
  local_source = unname(local_source_by_class),
  frozen_upstream_source =
    unname(upstream_source_by_class),
  formula = paste0(
    unname(local_feature_names),
    " - ",
    unname(upstream_source_by_class)
  )
)

combined_manifest <- rbindlist(
  list(
    copy(local_manifest)[
      ,
      module := "M1B_LOCAL_CONTRAST"
    ],
    copy(contrast_manifest)[
      ,
      module := "M1B_LOCAL_CONTRAST"
    ]
  ),
  fill = TRUE
)

radiogenic_manifest_rows <- list()
manifest_i <- 0L

for (group_name in names(radiogenic_groups)) {
  group_classes <- radiogenic_groups[[group_name]]

  local_proxy_name <- paste0(
    "r47__local_",
    group_name,
    "_proxy"
  )

  contrast_proxy_name <- paste0(
    "r47__contrast_",
    group_name,
    "_proxy"
  )

  manifest_i <- manifest_i + 1L
  radiogenic_manifest_rows[[manifest_i]] <- data.table(
    module = "M1B_RADIOGENIC_COMPACT",
    feature = local_proxy_name,
    feature_type = "compact_local_proxy",
    lithology_class = paste(
      group_classes,
      collapse = "+"
    ),
    local_source = paste(
      unname(local_feature_names[group_classes]),
      collapse = " + "
    ),
    frozen_upstream_source = NA_character_,
    formula = paste(
      unname(local_feature_names[group_classes]),
      collapse = " + "
    )
  )

  manifest_i <- manifest_i + 1L
  radiogenic_manifest_rows[[manifest_i]] <- data.table(
    module = "M1B_RADIOGENIC_COMPACT",
    feature = contrast_proxy_name,
    feature_type = "compact_contrast_proxy",
    lithology_class = paste(
      group_classes,
      collapse = "+"
    ),
    local_source = paste(
      unname(local_feature_names[group_classes]),
      collapse = " + "
    ),
    frozen_upstream_source = paste(
      unname(upstream_source_by_class[group_classes]),
      collapse = " + "
    ),
    formula = paste(
      unname(contrast_feature_names[group_classes]),
      collapse = " + "
    )
  )
}

radiogenic_manifest <- rbindlist(
  radiogenic_manifest_rows,
  fill = TRUE
)

feature_manifest <- rbindlist(
  list(
    local_manifest,
    contrast_manifest,
    combined_manifest,
    radiogenic_manifest
  ),
  fill = TRUE
)

feature_manifest[
  ,
  feature_order := seq_len(.N),
  by = module
]

setcolorder(
  feature_manifest,
  c(
    "module",
    "feature_order",
    "feature",
    "feature_type",
    "lithology_class",
    "local_source",
    "frozen_upstream_source",
    "formula"
  )
)

fwrite(
  feature_manifest,
  file.path(
    OUT_DIR,
    "feature_manifest.csv"
  )
)

module_features <- list(
  M1B_LOCAL =
    unname(local_feature_names),

  M1B_CONTRAST =
    unname(contrast_feature_names),

  M1B_LOCAL_CONTRAST =
    c(
      unname(local_feature_names),
      unname(contrast_feature_names)
    ),

  M1B_RADIOGENIC_COMPACT =
    radiogenic_feature_names
)

saveRDS(
  module_features,
  MODULE_RDS_FILE,
  compress = "xz"
)


# ------------------------------------------------------------------------------
# Save full model table and compact feature table
# ------------------------------------------------------------------------------

saveRDS(
  p0,
  FULL_TABLE_FILE,
  compress = "xz"
)

feature_table_columns <- unique(
  c(
    p0_site_column,
    sr_column,
    reserved_audit_columns,
    unname(upstream_source_by_class),
    unname(local_feature_names),
    unname(contrast_feature_names),
    radiogenic_feature_names
  )
)

saveRDS(
  p0[
    ,
    ..feature_table_columns
  ],
  FEATURE_TABLE_FILE,
  compress = "xz"
)


# ------------------------------------------------------------------------------
# Class mapping audit
# ------------------------------------------------------------------------------

class_mapping <- data.table(
  lithology_class = class_order,
  r46_local_source_column =
    unname(local_source_by_class),
  frozen_p0_upstream_column =
    unname(upstream_source_by_class),
  r47_local_feature =
    unname(local_feature_names),
  r47_contrast_feature =
    unname(contrast_feature_names)
)

fwrite(
  class_mapping,
  file.path(
    OUT_DIR,
    "lithology_class_mapping.csv"
  )
)


# ------------------------------------------------------------------------------
# Run summary and checksums
# ------------------------------------------------------------------------------

summary_lines <- c(
  "R47 HYBRID-HYBAS LOCAL LITHOLOGY BUILD",
  "=======================================",
  "",
  paste0("Project root: ", PROJECT_ROOT),
  paste0("P0 input: ", P0_FILE),
  paste0("Raw P0 candidate rows: ", p0_raw_n),
  paste0("Frozen-fold P0 rows retained: ", nrow(p0)),
  paste0("Rows excluded from frozen P0 scope: ", p0_raw_n - nrow(p0)),
  paste0("P0 scope ID column: ", p0_scope_site_column),
  paste0(
    "P0 sample-scope rule: complete cases across all p0__ fields"
  ),
  paste0(
    "Number of P0 baseline fields used for scope: ",
    length(p0_baseline_columns)
  ),
  paste0("R46 schema input: ", R46_CANDIDATE_FILE),
  paste0("Current assignment: ", ASSIGNMENT_FILE),
  paste0("Mismatch table: ", MISMATCH_FILE),
  paste0("GLiM asset directory: ", GLIM_DIR),
  "",
  paste0("Detected P0 site column: ", p0_site_column),
  paste0(
    "Detected assignment site column: ",
    assignment_site_column
  ),
  paste0(
    "Detected assignment HYBAS column: ",
    assignment_hybas_column
  ),
  paste0(
    "Detected mismatch site column: ",
    mismatch_site_column
  ),
  paste0(
    "Detected legacy HYBAS column: ",
    legacy_hybas_column
  ),
  paste0(
    "Detected mismatch current HYBAS column: ",
    mismatch_current_hybas_column
  ),
  paste0("Detected Sr response column: ", sr_column),
  "",
  paste0("Full P0 n: ", nrow(p0)),
  paste0("Sr >= 0.75 n: ", n_ge_075),
  paste0("Sr >= 0.80 n: ", n_ge_080),
  paste0("Legacy HYBAS overrides: ", sum(use_legacy)),
  paste0(
    "Legacy overrides with Sr >= 0.72: ",
    sum(use_legacy & sr_value >= 0.72)
  ),
  paste0(
    "Legacy overrides with Sr >= 0.75: ",
    sum(use_legacy & sr_value >= 0.75)
  ),
  paste0(
    "Legacy overrides with Sr >= 0.80: ",
    sum(use_legacy & sr_value >= 0.80)
  ),
  "",
  paste0(
    "Reproduced changed site x lithology cells: ",
    changed_cells_n
  ),
  paste0(
    "Reproduced distinct changed sites: ",
    changed_sites_n
  ),
  "",
  paste0(
    "Local fraction denominator: ",
    local_denominator
  ),
  paste0(
    "Frozen upstream denominator: ",
    upstream_denominator
  ),
  paste0(
    "Applied local scale factor: ",
    local_to_upstream_scale_factor
  ),
  "",
  paste0(
    "Lithology classes: ",
    paste(class_order, collapse = ", ")
  ),
  paste0(
    "Radiogenic compact features: ",
    paste(radiogenic_feature_names, collapse = ", ")
  ),
  "",
  paste0("Full table output: ", FULL_TABLE_FILE),
  paste0("Feature table output: ", FEATURE_TABLE_FILE),
  paste0("Module definition output: ", MODULE_RDS_FILE),
  "",
  "STATUS: ALL R47 INVARIANTS PASSED",
  "",
  "R session:",
  paste(
    capture.output(sessionInfo()),
    collapse = "\n"
  )
)

writeLines(
  summary_lines,
  file.path(
    OUT_DIR,
    "run_summary.txt"
  )
)

checksum_files <- c(
  FULL_TABLE_FILE,
  FEATURE_TABLE_FILE,
  MODULE_RDS_FILE,
  file.path(OUT_DIR, "feature_manifest.csv"),
  file.path(OUT_DIR, "coverage_audit.csv"),
  file.path(OUT_DIR, "hybas_join_audit.csv"),
  file.path(
    OUT_DIR,
    "legacy_current_local_lithology_comparison.csv"
  ),
  file.path(OUT_DIR, "lithology_class_mapping.csv"),
  file.path(OUT_DIR, "radiogenic_compact_rule.csv")
)

checksum_table <- data.table(
  file = checksum_files,
  md5 = unname(
    tools::md5sum(checksum_files)
  )
)

fwrite(
  checksum_table,
  file.path(
    OUT_DIR,
    "output_checksums.csv"
  )
)

message("")
message("==============================================================")
message("R47 completed successfully.")
message("Full table: ", FULL_TABLE_FILE)
message("Feature table: ", FEATURE_TABLE_FILE)
message("Module definitions: ", MODULE_RDS_FILE)
message("Audit directory: ", OUT_DIR)
message("==============================================================")
