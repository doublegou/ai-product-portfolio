#!/bin/bash
#SBATCH --job-name=sr_l6soil
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=08:00:00
#SBATCH --output=logs/sr_l6soil_%A_%a.out
#SBATCH --error=logs/sr_l6soil_%A_%a.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

unset R_HOME

export PROJ_DATA=$CONDA_PREFIX/share/proj
export PROJ_LIB=$CONDA_PREFIX/share/proj
export GDAL_DATA=$CONDA_PREFIX/share/gdal
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export GDAL_NUM_THREADS=$SLURM_CPUS_PER_TASK

cd "$SR_GLOBAL_DIR"

mkdir -p \
  logs \
  data_processed/global/soil_l6_by_region \
  outputs/global/soil_l6_qc

regions=(
  af
  ar
  as
  au
  eu
  gr
  na
  sa
  si
)

region="${regions[$SLURM_ARRAY_TASK_ID]}"

echo "Region: $region"

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/16_build_region_l6_soil.R \
  "$region"
