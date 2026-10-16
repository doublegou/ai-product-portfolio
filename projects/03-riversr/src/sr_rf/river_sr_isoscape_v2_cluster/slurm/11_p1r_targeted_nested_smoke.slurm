#!/usr/bin/env bash
#SBATCH --job-name=sr_p1r_nested
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=02:00:00
#SBATCH --output=logs/sr_p1r_nested_%j.out
#SBATCH --error=logs/sr_p1r_nested_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

mkdir -p \
  logs \
  outputs/p1r_targeted_smoke

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: $(hostname)"
echo "Start: $(date '+%Y-%m-%d %H:%M:%S')"

"${ENV_PREFIX}/bin/Rscript" \
  R/11_p1r_targeted_nested_smoke.R

echo "Finish: $(date '+%Y-%m-%d %H:%M:%S')"
