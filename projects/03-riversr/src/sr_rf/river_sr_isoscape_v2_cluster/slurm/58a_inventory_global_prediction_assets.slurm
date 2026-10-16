#!/bin/bash
#SBATCH --job-name=r58a_assets
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --output=logs/r58a_assets_%j.out
#SBATCH --error=logs/r58a_assets_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

out_dir="outputs/r58a_global_asset_inventory"

rm -rf "${out_dir}"

mkdir -p "${out_dir}"

python3 - <<'PY'
from pathlib import Path
import csv

root = Path.cwd()

out_dir = (
    root
    / "outputs"
    / "r58a_global_asset_inventory"
)

excluded_parts = {
    ".git",
    ".cache",
    "__pycache__",
    "r52_nested_spatial_rf",
    "r53_heldout_permutation",
    "_skipped_r53_partial",
}

data_extensions = {
    ".rds",
    ".rda",
    ".rdata",
    ".qs",
    ".fst",
    ".parquet",
    ".feather",
    ".arrow",
    ".csv",
    ".tsv",
    ".gpkg",
    ".shp",
    ".dbf",
    ".duckdb",
    ".sqlite",
    ".db",
    ".tif",
    ".tiff",
    ".nc",
    ".nc4",
    ".vrt",
}

keywords = {
    "hydrorivers",
    "hydro_rivers",
    "river_reach",
    "river_reaches",
    "global_reach",
    "global_river",
    "prediction_grid",
    "prediction_table",
    "predictor_table",
    "global_predict",
    "isoscape",
    "qrf",
    "quantile",
    "aoa",
    "dissimilarity",
    "reach_id",
    "hybas",
}

candidate_rows = []
large_rows = []

for path in root.rglob("*"):
    if not path.is_file():
        continue

    relative = path.relative_to(root)

    if any(
        part in excluded_parts
        for part in relative.parts
    ):
        continue

    suffix = path.suffix.lower()

    if suffix not in data_extensions:
        continue

    try:
        size_bytes = path.stat().st_size
    except OSError:
        continue

    lower_path = str(relative).lower()

    matched_keywords = sorted(
        keyword
        for keyword in keywords
        if keyword in lower_path
    )

    reasons = []

    if matched_keywords:
        reasons.append(
            "keyword:" +
            "|".join(matched_keywords)
        )

    if size_bytes >= 100 * 1024 * 1024:
        reasons.append(
            "size_ge_100MB"
        )

        large_rows.append(
            {
                "size_bytes": size_bytes,
                "size_mb": round(
                    size_bytes / 1024 / 1024,
                    3
                ),
                "extension": suffix,
                "path": str(relative),
            }
        )

    if reasons:
        candidate_rows.append(
            {
                "size_bytes": size_bytes,
                "size_mb": round(
                    size_bytes / 1024 / 1024,
                    3
                ),
                "extension": suffix,
                "reason": ";".join(reasons),
                "path": str(relative),
            }
        )

candidate_rows.sort(
    key=lambda row: (
        -row["size_bytes"],
        row["path"],
    )
)

large_rows.sort(
    key=lambda row: (
        -row["size_bytes"],
        row["path"],
    )
)

with (
    out_dir
    / "candidate_global_assets.tsv"
).open(
    "w",
    newline=""
) as handle:
    writer = csv.DictWriter(
        handle,
        fieldnames=[
            "size_bytes",
            "size_mb",
            "extension",
            "reason",
            "path",
        ],
        delimiter="\t",
    )

    writer.writeheader()
    writer.writerows(candidate_rows)

with (
    out_dir
    / "large_data_assets.tsv"
).open(
    "w",
    newline=""
) as handle:
    writer = csv.DictWriter(
        handle,
        fieldnames=[
            "size_bytes",
            "size_mb",
            "extension",
            "path",
        ],
        delimiter="\t",
    )

    writer.writeheader()
    writer.writerows(large_rows)

summary = [
    "R58A GLOBAL PREDICTION ASSET INVENTORY",
    "======================================",
    "",
    f"Candidate global assets: {len(candidate_rows)}",
    f"Data assets >=100 MB: {len(large_rows)}",
    "",
    "STATUS: R58A FILESYSTEM INVENTORY PASSED",
]

(
    out_dir
    / "filesystem_summary.txt"
).write_text(
    "\n".join(summary) + "\n"
)

print(
    "\n".join(summary)
)
PY

grep -RInE \
  --include='*.R' \
  --include='*.r' \
  --include='*.sh' \
  --include='*.slurm' \
  --include='*.Rmd' \
  --include='*.md' \
  'HydroRIVERS|8477883|8,477,883|8412388|8,412,388|global.*predict|predict.*global|QRF|quantile.*forest|write_parquet|read_parquet|saveRDS|readRDS|fst::|qs::|AOA|Dissimilarity' \
  R slurm . \
  2>/dev/null \
  | grep -v \
      'outputs/r52_nested_spatial_rf' \
  | sort \
  > "${out_dir}/script_keyword_hits.txt" \
  || true

du -h \
  --max-depth=2 \
  inputs outputs data derived_data \
  2>/dev/null \
  | sort -h \
  > "${out_dir}/directory_sizes.txt" \
  || true

{
  cat \
    "${out_dir}/filesystem_summary.txt"

  echo
  echo "Script keyword hits: $(
    wc -l \
      < "${out_dir}/script_keyword_hits.txt"
  )"

  echo
  echo "STATUS: R58A GLOBAL ASSET INVENTORY PASSED"
} \
  > "${out_dir}/run_summary.txt"

cat \
  "${out_dir}/run_summary.txt"
