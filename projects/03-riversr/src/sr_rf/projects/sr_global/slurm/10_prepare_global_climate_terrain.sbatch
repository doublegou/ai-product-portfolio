#!/bin/bash
#SBATCH --job-name=sr_climprep
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=08:00:00
#SBATCH --output=logs/sr_climprep_%j.out
#SBATCH --error=logs/sr_climprep_%j.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

unset R_HOME

export PROJ_DATA=$CONDA_PREFIX/share/proj
export PROJ_LIB=$CONDA_PREFIX/share/proj
export GDAL_DATA=$CONDA_PREFIX/share/gdal
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

export TMPDIR=/tmp/${USER}_sr_climprep_${SLURM_JOB_ID}
mkdir -p "$TMPDIR"

trap 'rm -rf "$TMPDIR"' EXIT

cd "$SR_GLOBAL_DIR"

mkdir -p \
  logs \
  data_processed/global/climate_terrain_2p5m \
  outputs/global/climate_terrain_qc

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/10_prepare_global_climate_terrain.R
