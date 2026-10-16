#!/usr/bin/env bash

#SBATCH --job-name=R49_inventory
#SBATCH --partition=batch
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=logs/R49_inventory_%j.out
#SBATCH --error=logs/R49_inventory_%j.err

set -euo pipefail

cd "$HOME/river_sr_isoscape_v2_cluster"

mkdir -p \
  logs \
  outputs/r49_master_feature_inventory

source slurm/common_env.sh

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK}"

# Larger candidate files are recorded but not loaded.
export R49_MAX_FILE_MB=1500

R_BIN="/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript"

echo "============================================================"
echo "R49 master feature inventory"
echo "Job ID: ${SLURM_JOB_ID:-NA}"
echo "Host: $(hostname)"
echo "Start: $(date --iso-8601=seconds)"
echo "Working directory: $(pwd)"
echo "============================================================"

"${R_BIN}" --vanilla \
  R/49_build_master_feature_inventory.R

echo "============================================================"
echo "R49 completed successfully"
echo "End: $(date --iso-8601=seconds)"
echo "============================================================"

cat \
  outputs/r49_master_feature_inventory/run_summary.txt
