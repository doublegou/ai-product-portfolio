#!/usr/bin/env bash
#SBATCH --job-name=sr_v3_review
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=12G
#SBATCH --time=02:00:00

set -euo pipefail
: "${RIVER_SR_ROOT:?}"; : "${RIVER_SR_RUN_ID:?}"
set +u; source /etc/profile; set -u
module purge; module load R-4.4.3
cd "$RIVER_SR_ROOT"
Rscript training/base/v3/scripts/run.R check --run-id "$RIVER_SR_RUN_ID"
