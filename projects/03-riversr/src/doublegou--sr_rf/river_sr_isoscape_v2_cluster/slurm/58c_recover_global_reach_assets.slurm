#!/bin/bash
#SBATCH --job-name=r58c_recover
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=01:00:00
#SBATCH --output=logs/r58c_recover_%j.out
#SBATCH --error=logs/r58c_recover_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

out_dir="outputs/r58c_global_asset_recovery"

mkdir -p "${out_dir}"

rm -f \
  "${out_dir}/candidate_global_files.tsv" \
  "${out_dir}/all_large_data_files.tsv" \
  "${out_dir}/candidate_directories.txt" \
  "${out_dir}/storage_inventory.txt" \
  "${out_dir}/run_summary.txt"

python3 - <<'PY'
from pathlib import Path
import csv
import os

home = Path("/home/zhangmeng")

project = (
    home
    / "river_sr_isoscape_v2_cluster"
)

out_dir = (
    project
    / "outputs"
    / "r58c_global_asset_recovery"
)

skip_directory_names = {
    ".cache",
    ".conda",
    ".local",
    ".mamba",
    ".micromamba",
    ".npm",
    ".rustup",
    ".cargo",
    ".vscode-server",
    "__pycache__",
    "node_modules",
    "site-packages",
    "lib64",
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
    ".csv.gz",
    ".tsv",
    ".tsv.gz",
    ".gpkg",
    ".shp",
    ".dbf",
    ".duckdb",
    ".sqlite",
    ".sqlite3",
    ".db",
    ".pkl",
    ".pickle",
}

keywords = {
    "hydroriver",
    "hydro_river",
    "hyriv",
    "river_reach",
    "riverreach",
    "reaches",
    "global_predict",
    "globalpredict",
    "global_predictor",
    "predictor_global",
    "isoscape",
    "qrf",
    "aoa",
    "reach_predictor",
    "prediction_reach",
}

candidate_rows = []
large_rows = []

for current_root, directory_names, file_names in os.walk(
    home,
    topdown=True,
    followlinks=False,
):
    directory_names[:] = [
        directory_name
        for directory_name in directory_names
        if directory_name not in skip_directory_names
    ]

    current_path = Path(current_root)

    for file_name in file_names:
        path = current_path / file_name

        try:
            size_bytes = path.stat().st_size
        except OSError:
            continue

        lower_path = str(path).lower()

        suffixes = "".join(
            path.suffixes[-2:]
        ).lower()

        extension = (
            suffixes
            if suffixes in data_extensions
            else path.suffix.lower()
        )

        if extension not in data_extensions:
            continue

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

        if size_bytes >= 20 * 1024 * 1024:
            reasons.append(
                "size_ge_20MB"
            )

        if size_bytes >= 100 * 1024 * 1024:
            large_rows.append(
                {
                    "size_bytes": size_bytes,
                    "size_mb": round(
                        size_bytes / 1024 / 1024,
                        3
                    ),
                    "extension": extension,
                    "path": str(path),
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
                    "extension": extension,
                    "reason": ";".join(reasons),
                    "inside_current_project": str(
                        path
                    ).startswith(
                        str(project)
                    ),
                    "path": str(path),
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
    / "candidate_global_files.tsv"
).open(
    "w",
    newline="",
) as handle:
    writer = csv.DictWriter(
        handle,
        fieldnames=[
            "size_bytes",
            "size_mb",
            "extension",
            "reason",
            "inside_current_project",
            "path",
        ],
        delimiter="\t",
    )

    writer.writeheader()
    writer.writerows(candidate_rows)

with (
    out_dir
    / "all_large_data_files.tsv"
).open(
    "w",
    newline="",
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
    "R58C GLOBAL REACH ASSET RECOVERY",
    "================================",
    "",
    f"Candidate files: {len(candidate_rows)}",
    f"Data files >=100 MB: {len(large_rows)}",
    "",
    "STATUS: R58C HOME ASSET SEARCH PASSED",
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

find \
  /home/zhangmeng \
  -maxdepth 4 \
  -type d \
  \( \
    -iname '*river*' \
    -o \
    -iname '*hydro*' \
    -o \
    -iname '*isoscape*' \
    -o \
    -iname '*strontium*' \
    -o \
    -iname '*sr_*' \
  \) \
  2>/dev/null \
  | sort \
  > "${out_dir}/candidate_directories.txt"

{
  echo "===== FILESYSTEMS ====="
  df -h

  echo
  echo "===== MOUNTS RELEVANT TO USER STORAGE ====="
  mount \
    | grep -E \
      '/home|/data|/share|/work|/scratch|/mnt' \
    || true
} \
  > "${out_dir}/storage_inventory.txt"

{
  cat \
    "${out_dir}/filesystem_summary.txt"

  echo
  echo "Candidate directories: $(
    wc -l \
      < "${out_dir}/candidate_directories.txt"
  )"

  echo
  echo "STATUS: R58C GLOBAL ASSET RECOVERY PASSED"
} \
  > "${out_dir}/run_summary.txt"

cat \
  "${out_dir}/run_summary.txt"
