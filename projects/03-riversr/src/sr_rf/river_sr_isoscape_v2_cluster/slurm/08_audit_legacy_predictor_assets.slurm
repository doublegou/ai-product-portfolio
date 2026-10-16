#!/usr/bin/env bash
#SBATCH --job-name=sr_asset_audit
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/sr_asset_audit_%j.out
#SBATCH --error=logs/sr_asset_audit_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

mkdir -p \
  logs \
  outputs/legacy_asset_audit

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: $(hostname)"
echo "Start: $(date '+%Y-%m-%d %H:%M:%S')"

"${ENV_PREFIX}/bin/Rscript" \
  R/08_audit_legacy_predictor_assets.R

echo "Finish: $(date '+%Y-%m-%d %H:%M:%S')"
