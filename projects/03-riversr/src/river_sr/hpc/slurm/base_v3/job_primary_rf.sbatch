#!/usr/bin/env bash
#SBATCH --job-name=sr_v3_rf
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=36:00:00

set -euo pipefail
: "${RIVER_SR_ROOT:?}"; : "${RIVER_SR_RUN_ID:?}"; : "${SLURM_ARRAY_TASK_ID:?}"
set +u; source /etc/profile; set -u
module purge; module load R-4.4.3
cd "$RIVER_SR_ROOT"
Rscript training/base/v3/scripts/run.R primary --model rf --task "$SLURM_ARRAY_TASK_ID" --run-id "$RIVER_SR_RUN_ID"
