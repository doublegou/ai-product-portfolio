#!/bin/bash
#SBATCH --job-name=sr_map_geometry
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=06:00:00
#SBATCH --output=logs/sr_map_geometry_%j.out
#SBATCH --error=logs/sr_map_geometry_%j.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/usr/local/bin:/usr/bin:/bin
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

PROJ_DB=$(find "$CONDA_PREFIX" \
  -type f -name proj.db -print -quit)

GDAL_MARKER=$(find "$CONDA_PREFIX" \
  -type f \
  \( -name gdalvrt.xsd -o -name header.dxf \) \
  -print -quit)

export PROJ_DATA="$(dirname "$PROJ_DB")"
export PROJ_LIB="$PROJ_DATA"
export GDAL_DATA="$(dirname "$GDAL_MARKER")"

export SR_MAP_MAX_ORD_FLOW=5

cd "$SR_GLOBAL_DIR"

mkdir -p logs

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/26_build_global_major_river_map_geometry.R
