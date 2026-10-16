#!/bin/bash
#SBATCH --job-name=sr_l6clim
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=16:00:00
#SBATCH --output=logs/sr_l6clim_%A_%a.out
#SBATCH --error=logs/sr_l6clim_%A_%a.err

set -euo pipefail

regions=(
  af ar as au eu gr na sa si
)

region=${regions[$SLURM_ARRAY_TASK_ID]}

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

unset R_HOME

export PROJ_DATA=$CONDA_PREFIX/share/proj
export PROJ_LIB=$CONDA_PREFIX/share/proj
export GDAL_DATA=$CONDA_PREFIX/share/gdal
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

export TMPDIR=/tmp/${USER}_sr_l6clim_${SLURM_JOB_ID}
export SR_BASIN_CHUNK_SIZE=100

mkdir -p "$TMPDIR"

trap 'rm -rf "$TMPDIR"' EXIT

cd "$SR_GLOBAL_DIR"

mkdir -p \
  logs \
  data_processed/global/climate_terrain_l6_by_region \
  outputs/global/climate_terrain_l6_qc

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/11_build_region_l6_climate_terrain.R \
  "$region"
