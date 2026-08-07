#!/bin/bash
#SBATCH --job-name=r57b_geo_cv
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=logs/r57b_geo_cv_%j.out
#SBATCH --error=logs/r57b_geo_cv_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  --vanilla \
  R/57b_aggregate_geological_regime_validation.R
