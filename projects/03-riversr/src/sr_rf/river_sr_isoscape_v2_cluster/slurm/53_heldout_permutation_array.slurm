#!/bin/bash
#SBATCH --job-name=r53_perm
#SBATCH --array=1-45%5
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=24:00:00
#SBATCH --output=logs/r53_perm_%A_%a.out
#SBATCH --error=logs/r53_perm_%A_%a.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

export R53_TASK_ID="${SLURM_ARRAY_TASK_ID}"
export R53_THREADS="${SLURM_CPUS_PER_TASK}"
export R53_REPEATS=10

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  --vanilla \
  R/53a_run_heldout_permutation_task.R
