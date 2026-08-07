#!/bin/bash
#SBATCH --job-name=r58e_sources
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=logs/r58e_sources_%j.out
#SBATCH --error=logs/r58e_sources_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  --vanilla \
  R/58e_trace_legacy_predictor_sources.R
