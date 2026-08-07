#!/bin/bash
#SBATCH --job-name=r58i_climate
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/r58i_climate_%j.out
#SBATCH --error=logs/r58i_climate_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  --vanilla \
  R/58i_audit_climate_deployment_sources.R
