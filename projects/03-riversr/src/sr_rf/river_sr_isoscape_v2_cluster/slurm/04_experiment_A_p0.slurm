#!/usr/bin/env bash
#SBATCH --job-name=sr_p0_A
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=logs/sr_p0_A_%j.out
#SBATCH --error=logs/sr_p0_A_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

mkdir -p \
  logs \
  outputs/experiment_A_p0

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: $(hostname)"
echo "CPUs: ${SLURM_CPUS_PER_TASK}"
echo "Start: $(date '+%Y-%m-%d %H:%M:%S')"

"${ENV_PREFIX}/bin/Rscript" \
  R/04_experiment_A_p0.R

echo "Finish: $(date '+%Y-%m-%d %H:%M:%S')"
