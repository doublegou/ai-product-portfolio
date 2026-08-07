#!/bin/bash
#SBATCH --job-name=r58d_schema
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=logs/r58d_schema_%j.out
#SBATCH --error=logs/r58d_schema_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  --vanilla \
  R/58d_audit_legacy_global_prediction_schema.R
