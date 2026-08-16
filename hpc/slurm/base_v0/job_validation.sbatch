#!/usr/bin/env bash
#SBATCH --job-name=sr_v0_cv
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=16G
#SBATCH --time=04:00:00

set -euo pipefail

: "${RIVER_SR_ROOT:?RIVER_SR_ROOT is required}"
: "${RIVER_SR_RUN_ID:?RIVER_SR_RUN_ID is required}"

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
set +u
source /etc/profile
set -u
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
module purge
module load R-4.4.3
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
cd "$RIVER_SR_ROOT"

schemes=(spatial_500 spatial_1000 spatial_1500 reference)
task_index="${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is required}"
scheme_index=$((task_index / 5))
outer_fold=$((task_index % 5 + 1))
scheme="${schemes[$scheme_index]}"

Rscript training/base/v0/scripts/run.R \
  --mode full \
  --scheme "$scheme" \
  --outer-fold "$outer_fold"
