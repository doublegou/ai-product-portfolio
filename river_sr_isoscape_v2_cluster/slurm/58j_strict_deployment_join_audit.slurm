#!/bin/bash
#SBATCH --job-name=r58j_join
#SBATCH --cpus-per-task=1
#SBATCH --mem=48G
#SBATCH --time=01:30:00
#SBATCH --output=logs/r58j_join_%j.out
#SBATCH --error=logs/r58j_join_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  --vanilla \
  R/58j_strict_deployment_join_audit.R
