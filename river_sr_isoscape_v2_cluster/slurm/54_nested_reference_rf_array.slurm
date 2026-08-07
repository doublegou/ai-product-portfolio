#!/bin/bash
#SBATCH --job-name=r54_ref_rf
#SBATCH --array=1-15%5
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=24:00:00
#SBATCH --output=logs/r54_ref_rf_%A_%a.out
#SBATCH --error=logs/r54_ref_rf_%A_%a.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

export R54_TASK_ID="${SLURM_ARRAY_TASK_ID}"
export R54_THREADS="${SLURM_CPUS_PER_TASK}"
export R54_INNER_TREES=500
export R54_OUTER_TREES=1500
export R54_SEED_BASE=540000

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  --vanilla \
  R/54b_run_nested_reference_rf_task.R
