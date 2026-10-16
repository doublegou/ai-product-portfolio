#!/usr/bin/env bash
#SBATCH --job-name=sr_p0_regions
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH --output=logs/sr_p0_regions_%j.out
#SBATCH --error=logs/sr_p0_regions_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

mkdir -p \
  logs \
  outputs/p0_failure_regions

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: $(hostname)"
echo "Start: $(date '+%Y-%m-%d %H:%M:%S')"

"${ENV_PREFIX}/bin/Rscript" \
  R/06_p0_failure_regions.R

echo "Finish: $(date '+%Y-%m-%d %H:%M:%S')"
