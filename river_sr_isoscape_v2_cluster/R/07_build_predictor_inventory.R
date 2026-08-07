source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

library(dplyr)
library(readr)
library(tibble)

out_dir <- file.path(
  project_root(),
  "outputs/predictor_inventory"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

# ------------------------------------------------------------
# 1. Known predictor-bearing files
# ------------------------------------------------------------

source_paths <- c(
  current_model_table = file.path(
    project_root(),
    "data/processed/model_table.rds"
  ),

  current_predictors = file.path(
    project_root(),
    "data/external/predictors_at_sites.rds"
  ),

  legacy_global_complete = file.path(
    Sys.getenv("HOME"),
    paste0(
      "projects/sr_global/data_processed/global/",
      "global_model_sites_5km_with_geology_",
      "climate_terrain_soil_complete.rds"
    )
  )
)

source_status <- tibble(
  source_name = names(source_paths),
  path = unname(source_paths),
  exists = file.exists(source_paths)
)

write_csv(
  source_status,
  file.path(
    out_dir,
    "predictor_source_files.csv"
  )
)

print(source_status)

read_predictor_object <- function(
    path,
    source_name
) {
  if (!file.exists(path)) {
    return(NULL)
  }

  object <- readRDS(path)

  if (
    !is.data.frame(object) &&
    !inherits(object, "tbl")
  ) {
    stop(
      source_name,
      " is not a data frame."
    )
  }

  object
}

# ------------------------------------------------------------
# 2. Inventory all existing columns
# ------------------------------------------------------------

inventory_list <- list()

for (
  source_name in names(source_paths)
) {
  path <- source_paths[[source_name]]

  object <- read_predictor_object(
    path,
    source_name
  )

  if (is.null(object)) {
    next
  }

  source_inventory <- tibble(
    source_name = source_name,
    source_path = path,
    n_rows = nrow(object),
    column_name = names(object),

    storage_class = vapply(
      object,
      function(x) {
        paste(
          class(x),
          collapse = ";"
        )
      },
      character(1)
    ),

    nonmissing_n = vapply(
      object,
      function(x) {
        sum(!is.na(x))
      },
      integer(1)
    ),

    unique_n = vapply(
      object,
      function(x) {
        dplyr::n_distinct(
          x,
          na.rm = TRUE
        )
      },
      integer(1)
    )
  ) |>
    mutate(
      nonmissing_fraction =
        nonmissing_n / n_rows
    )

  inventory_list[[
    length(inventory_list) + 1L
  ]] <- source_inventory
}

existing_inventory <- bind_rows(
  inventory_list
)

if (nrow(existing_inventory) == 0L) {
  stop(
    "No predictor-bearing source files could be read."
  )
}

classify_existing_column <- function(x) {
  x_lower <- tolower(x)

  case_when(
    grepl(
      "^p0__",
      x_lower
    ) ~
      "P0 legacy predictor",

    grepl(
      "longitude|latitude|sp_x|sp_y|sp_z",
      x_lower
    ) ~
      "spatial coordinate",

    grepl(
      "bedrock.*sr|sr.*bedrock|radiogenic",
      x_lower
    ) ~
      "bedrock Sr / radiogenic",

    grepl(
      "carbonate|evaporite|siliciclastic|metamorphic|plutonic|volcanic|lith",
      x_lower
    ) ~
      "lithology",

    grepl(
      "geol.*age|geological.*age|rock.*age",
      x_lower
    ) ~
      "geological age",

    grepl(
      "discharge|runoff|baseflow|recharge|flow|catch|upland|stream|river",
      x_lower
    ) ~
      "river network / hydrology",

    grepl(
      "permeab|porosity|aquifer|groundwater",
      x_lower
    ) ~
      "hydrogeology",

    grepl(
      "glacier|snow|permafrost|ice",
      x_lower
    ) ~
      "cryosphere",

    grepl(
      "elev|slope|relief|rugged|terrain",
      x_lower
    ) ~
      "terrain",

    grepl(
      "precip|temperature|bio[0-9]|aridity|et0|climate",
      x_lower
    ) ~
      "climate",

    grepl(
      "clay|soil|weather",
      x_lower
    ) ~
      "soil / weathering",

    grepl(
      "lake|endorheic|salin",
      x_lower
    ) ~
      "lake / saline",

    TRUE ~
      "other"
  )
}

existing_inventory <- existing_inventory |>
  mutate(
    inferred_group =
      classify_existing_column(
        column_name
      )
  ) |>
  arrange(
    inferred_group,
    source_name,
    column_name
  )

write_csv(
  existing_inventory,
  file.path(
    out_dir,
    "existing_predictor_columns.csv"
  )
)

# ------------------------------------------------------------
# 3. Candidate A1-A4 predictor architecture
# ------------------------------------------------------------

candidate_inventory <- tribble(
  ~stage, ~candidate_name, ~process_family,
  ~aggregation, ~priority, ~required_input,
  ~calculation_logic, ~search_regex,

  "A1", "local_bedrock_sr",
  "radiogenic source", "local",
  "critical", "bedrock Sr raster",
  "Bedrock Sr value at the sampling river cell",
  "local.*bedrock.*sr|bedrock.*sr.*local|local_sr",

  "A1", "local_geological_age",
  "radiogenic source", "local",
  "critical", "geological age raster",
  "Geological age at the local river cell",
  "local.*geol.*age|geol.*age.*local|rock.*age",

  "A1", "local_lithology",
  "geological source", "local",
  "high", "GLiM or equivalent lithology",
  "Local lithological class or fractions",
  "local.*lith|local.*geo|geology_local",

  "A1", "runoff",
  "hydrological modifier", "local/upstream",
  "critical", "global runoff raster",
  "Mean annual runoff or water-yield proxy",
  "runoff|water.*yield",

  "A1", "baseflow",
  "hydrological modifier", "local/upstream",
  "high", "global baseflow raster",
  "Baseflow index or baseflow contribution",
  "baseflow|base_flow",

  "A1", "groundwater_recharge",
  "hydrological modifier", "local/upstream",
  "medium", "groundwater recharge raster",
  "Groundwater recharge contribution",
  "recharge|groundwater.*recharge",

  "A1", "permeability",
  "hydrogeology", "local/upstream",
  "high", "global permeability raster",
  "Subsurface permeability",
  "permeab",

  "A1", "porosity",
  "hydrogeology", "local/upstream",
  "medium", "global porosity raster",
  "Subsurface porosity",
  "porosity",

  "A1", "relief",
  "erosion modifier", "local/upstream",
  "critical", "DEM",
  "Local or upstream relief",
  "relief|rugged",

  "A1", "slope_p90",
  "erosion modifier", "upstream distribution",
  "high", "DEM and upstream network",
  "90th percentile upstream slope",
  "slope.*p90|p90.*slope",

  "A1", "glacier_fraction",
  "glacial modifier", "upstream area fraction",
  "critical", "global glacier extent",
  "Fraction of upstream area covered by glacier",
  "glacier|glaciated",

  "A1", "permafrost_fraction",
  "glacial modifier", "upstream area fraction",
  "medium", "global permafrost extent",
  "Fraction of upstream area under permafrost",
  "permafrost",

  "A1", "aridity",
  "arid modifier", "local/upstream",
  "high", "precipitation and ET0",
  "Aridity index or ET0/precipitation",
  "aridity|ai_ratio|et0.*precip",

  "A2", "up_bedrock_sr_area_mean",
  "radiogenic source", "upstream area weighted",
  "critical", "bedrock Sr raster and upstream areas",
  "Area-weighted mean upstream bedrock Sr",
  "up.*bedrock.*sr.*mean|bedrock.*sr.*area",

  "A2", "up_bedrock_sr_median",
  "radiogenic source", "upstream distribution",
  "critical", "bedrock Sr raster and upstream network",
  "Median upstream bedrock Sr",
  "up.*bedrock.*sr.*median",

  "A2", "up_bedrock_sr_p75",
  "radiogenic source", "upstream distribution",
  "high", "bedrock Sr raster and upstream network",
  "75th percentile upstream bedrock Sr",
  "up.*bedrock.*sr.*p75|bedrock.*sr.*q75",

  "A2", "up_bedrock_sr_p90",
  "radiogenic source", "upstream distribution",
  "critical", "bedrock Sr raster and upstream network",
  "90th percentile upstream bedrock Sr",
  "up.*bedrock.*sr.*p90|bedrock.*sr.*q90",

  "A2", "up_bedrock_sr_p95",
  "radiogenic source", "upstream distribution",
  "critical", "bedrock Sr raster and upstream network",
  "95th percentile upstream bedrock Sr",
  "up.*bedrock.*sr.*p95|bedrock.*sr.*q95",

  "A2", "up_bedrock_sr_sd",
  "radiogenic source", "upstream heterogeneity",
  "high", "bedrock Sr raster and upstream network",
  "Standard deviation of upstream bedrock Sr",
  "up.*bedrock.*sr.*sd",

  "A2", "up_bedrock_sr_iqr",
  "radiogenic source", "upstream heterogeneity",
  "high", "bedrock Sr raster and upstream network",
  "IQR of upstream bedrock Sr",
  "up.*bedrock.*sr.*iqr",

  "A2", "up_fraction_sr_gt_072",
  "radiogenic source", "upstream area fraction",
  "critical", "bedrock Sr raster and upstream network",
  "Fraction of upstream area with bedrock Sr > 0.72",
  "fraction.*sr.*072|sr.*gt.*072",

  "A2", "up_fraction_sr_gt_073",
  "radiogenic source", "upstream area fraction",
  "high", "bedrock Sr raster and upstream network",
  "Fraction of upstream area with bedrock Sr > 0.73",
  "fraction.*sr.*073|sr.*gt.*073",

  "A2", "up_fraction_sr_gt_074",
  "radiogenic source", "upstream area fraction",
  "medium", "bedrock Sr raster and upstream network",
  "Fraction of upstream area with bedrock Sr > 0.74",
  "fraction.*sr.*074|sr.*gt.*074",

  "A2", "up_metamorphic_fraction",
  "radiogenic source", "upstream area weighted",
  "critical", "upstream lithology fractions",
  "Fraction of upstream area under metamorphic lithology",
  "up.*metamorphic.*frac|metamorphic.*fraction",

  "A2", "up_plutonic_fraction",
  "radiogenic source", "upstream area weighted",
  "critical", "upstream lithology fractions",
  "Fraction of upstream area under plutonic lithology",
  "up.*plutonic.*frac|plutonic.*fraction",

  "A2", "lithological_diversity",
  "source heterogeneity", "upstream",
  "high", "upstream lithology fractions",
  "Diversity or entropy of upstream lithologies",
  "lith.*divers|lith.*entropy|geo.*divers",

  "A2", "local_minus_up_area_mean",
  "local-upstream contrast", "contrast",
  "critical", "local and upstream bedrock Sr",
  "Local bedrock Sr minus upstream area mean",
  "local.*minus.*up.*mean",

  "A2", "local_minus_up_p90",
  "local-upstream contrast", "contrast",
  "high", "local bedrock Sr and upstream p90",
  "Local bedrock Sr minus upstream p90",
  "local.*minus.*up.*p90",

  "A2", "up_p90_minus_mean",
  "source heterogeneity", "contrast",
  "critical", "upstream p90 and mean",
  "Upstream p90 minus upstream mean",
  "p90.*minus.*mean",

  "A3", "up_bedrock_sr_runoff_mean",
  "radiogenic source", "upstream runoff weighted",
  "critical", "bedrock Sr and runoff rasters",
  "Runoff-weighted upstream bedrock Sr",
  "bedrock.*sr.*runoff|runoff.*bedrock.*sr",

  "A3", "up_metamorphic_runoff_fraction",
  "radiogenic source", "upstream runoff weighted",
  "high", "lithology and runoff rasters",
  "Runoff-weighted metamorphic contribution",
  "metamorphic.*runoff",

  "A3", "up_plutonic_runoff_fraction",
  "radiogenic source", "upstream runoff weighted",
  "high", "lithology and runoff rasters",
  "Runoff-weighted plutonic contribution",
  "plutonic.*runoff",

  "A3", "up_glacier_runoff_fraction",
  "glacial modifier", "upstream runoff weighted",
  "high", "glacier and runoff rasters",
  "Fraction of upstream runoff originating in glacier cells",
  "glacier.*runoff",

  "A4", "radiogenic_p90_x_runoff",
  "radiogenic interaction", "interaction",
  "critical", "upstream bedrock p90 and runoff",
  "up_bedrock_sr_p90 multiplied by runoff",
  "radiogenic.*p90.*runoff|p90.*runoff",

  "A4", "radiogenic_fraction_x_relief",
  "radiogenic interaction", "interaction",
  "critical", "radiogenic fraction and relief",
  "Radiogenic source fraction multiplied by relief",
  "radiogenic.*relief",

  "A4", "radiogenic_fraction_x_glacier",
  "glacial-radiogenic interaction", "interaction",
  "critical", "radiogenic and glacier fractions",
  "Radiogenic source fraction multiplied by glacier fraction",
  "radiogenic.*glacier|glacier.*radiogenic",

  "A4", "bedrock_sr_x_glacier",
  "glacial-radiogenic interaction", "interaction",
  "high", "bedrock Sr and glacier fraction",
  "Bedrock Sr multiplied by glacier fraction",
  "bedrock.*sr.*glacier|glacier.*bedrock.*sr",

  "A4", "carbonate_fraction_x_baseflow",
  "carbonate interaction", "interaction",
  "high", "carbonate fraction and baseflow",
  "Carbonate fraction multiplied by baseflow",
  "carbonate.*baseflow",

  "A4", "evaporite_fraction_x_aridity",
  "arid-evaporite interaction", "interaction",
  "high", "evaporite fraction and aridity",
  "Evaporite fraction multiplied by aridity",
  "evaporite.*arid",

  "A4", "bedrock_sr_x_clay",
  "weathering interaction", "interaction",
  "medium", "bedrock Sr and soil clay",
  "Bedrock Sr multiplied by clay fraction",
  "bedrock.*sr.*clay|clay.*bedrock.*sr"
)

# ------------------------------------------------------------
# 4. Search candidate variables in existing columns
# ------------------------------------------------------------

current_sources <- c(
  "current_model_table",
  "current_predictors"
)

candidate_matches <- candidate_inventory |>
  rowwise() |>
  mutate(
    matched_columns = {
      matched <- existing_inventory |>
        filter(
          grepl(
            search_regex,
            column_name,
            ignore.case = TRUE
          )
        )

      if (nrow(matched) == 0L) {
        ""
      } else {
        paste(
          unique(
            matched$column_name
          ),
          collapse = "; "
        )
      }
    },

    matched_sources = {
      matched <- existing_inventory |>
        filter(
          grepl(
            search_regex,
            column_name,
            ignore.case = TRUE
          )
        )

      if (nrow(matched) == 0L) {
        ""
      } else {
        paste(
          unique(
            matched$source_name
          ),
          collapse = "; "
        )
      }
    },

    availability = {
      matched <- existing_inventory |>
        filter(
          grepl(
            search_regex,
            column_name,
            ignore.case = TRUE
          )
        )

      if (
        any(
          matched$source_name %in%
            current_sources
        )
      ) {
        "already_available_current"
      } else if (nrow(matched) > 0L) {
        "possibly_available_legacy"
      } else {
        "not_found"
      }
    }
  ) |>
  ungroup() |>
  arrange(
    factor(
      priority,
      levels = c(
        "critical",
        "high",
        "medium"
      )
    ),
    stage,
    process_family,
    candidate_name
  )

write_csv(
  candidate_matches,
  file.path(
    out_dir,
    "candidate_predictor_inventory.csv"
  )
)

priority_missing <- candidate_matches |>
  filter(
    priority %in% c(
      "critical",
      "high"
    ),
    availability !=
      "already_available_current"
  )

write_csv(
  priority_missing,
  file.path(
    out_dir,
    "priority_predictor_gaps.csv"
  )
)

# ------------------------------------------------------------
# 5. Summaries
# ------------------------------------------------------------

availability_summary <- candidate_matches |>
  count(
    stage,
    priority,
    availability,
    name = "n_predictors"
  ) |>
  arrange(
    stage,
    priority,
    availability
  )

write_csv(
  availability_summary,
  file.path(
    out_dir,
    "candidate_availability_summary.csv"
  )
)

existing_group_summary <- existing_inventory |>
  count(
    source_name,
    inferred_group,
    name = "n_columns"
  ) |>
  arrange(
    source_name,
    desc(n_columns)
  )

write_csv(
  existing_group_summary,
  file.path(
    out_dir,
    "existing_group_summary.csv"
  )
)

cat("\nCandidate availability summary:\n")

print(
  availability_summary,
  n = Inf,
  width = Inf
)

cat("\nCritical and high-priority predictor gaps:\n")

print(
  priority_missing |>
    select(
      stage,
      candidate_name,
      process_family,
      priority,
      availability,
      matched_columns,
      matched_sources,
      required_input
    ),
  n = Inf,
  width = Inf
)

log_msg(
  "Predictor inventory complete: ",
  out_dir
)
