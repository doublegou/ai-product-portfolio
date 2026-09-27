#!/bin/bash
#SBATCH --job-name=sr_clay08
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=04:00:00
#SBATCH --output=logs/sr_clay08_%j.out
#SBATCH --error=logs/sr_clay08_%j.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

unset R_HOME

export PROJ_DATA=$CONDA_PREFIX/share/proj
export PROJ_LIB=$CONDA_PREFIX/share/proj
export GDAL_DATA=$CONDA_PREFIX/share/gdal
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

export SR_NTHREADS=$SLURM_CPUS_PER_TASK

cd "$SR_GLOBAL_DIR"

mkdir -p \
  logs \
  outputs/global/soil_models_coverage08 \
  models/global

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/19_global_upstream_clay_coverage08.R
