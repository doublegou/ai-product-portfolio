#!/usr/bin/env bash

#SBATCH --job-name=R47_local_lith
#SBATCH --cpus-per-task=2
#SBATCH --mem=24G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -eo pipefail

cd ~/river_sr_isoscape_v2_cluster

mkdir -p \
  logs \
  outputs/r47_hybrid_local_lithology

source slurm/common_env.sh

set -u

export PROJECT_ROOT="$HOME/river_sr_isoscape_v2_cluster"
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-2}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK:-2}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK:-2}"
export VECLIB_MAXIMUM_THREADS="${SLURM_CPUS_PER_TASK:-2}"
export NUMEXPR_NUM_THREADS="${SLURM_CPUS_PER_TASK:-2}"

R_BIN="/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript"

if [[ ! -x "${R_BIN}" ]]; then
  echo "ERROR: Rscript is not executable at:"
  echo "  ${R_BIN}"
  exit 1
fi

echo "============================================================"
echo "R47 started"
echo "Host: $(hostname)"
echo "Job ID: ${SLURM_JOB_ID:-NA}"
echo "Working directory: $(pwd)"
echo "Rscript: ${R_BIN}"
echo "Start time: $(date --iso-8601=seconds)"
echo "============================================================"

"${R_BIN}" --vanilla \
  scripts/r47_build_hybrid_hybas_local_lithology.R

echo "============================================================"
echo "R47 finished successfully"
echo "End time: $(date --iso-8601=seconds)"
echo "============================================================"

cat outputs/r47_hybrid_local_lithology/run_summary.txt
