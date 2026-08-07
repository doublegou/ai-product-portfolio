#!/usr/bin/env bash

#SBATCH --job-name=R48_lith_RF
#SBATCH --partition=batch
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/R48_lith_RF_%j.out
#SBATCH --error=logs/R48_lith_RF_%j.err

set -euo pipefail

cd "$HOME/river_sr_isoscape_v2_cluster"

mkdir -p \
  logs \
  outputs/r48_controlled_local_lithology_rf_1500

source slurm/common_env.sh

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK}"

R_BIN="/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript"

echo "============================================================"
echo "R48 controlled local-lithology RF experiment"
echo "Job ID: ${SLURM_JOB_ID:-NA}"
echo "Host: $(hostname)"
echo "Start: $(date --iso-8601=seconds)"
echo "Working directory: $(pwd)"
echo "============================================================"

"${R_BIN}" --vanilla \
  R/48_controlled_local_lithology_rf_1500.R

echo "============================================================"
echo "R48 completed successfully"
echo "End: $(date --iso-8601=seconds)"
echo "============================================================"

cat \
  outputs/r48_controlled_local_lithology_rf_1500/run_summary.txt
