#!/usr/bin/env bash
#SBATCH --job-name=sr_v3_final
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem=32G
#SBATCH --time=12:00:00

set -euo pipefail
: "${RIVER_SR_ROOT:?}"; : "${RIVER_SR_RUN_ID:?}"
set +u; source /etc/profile; set -u
module purge; module load R-4.4.3
cd "$RIVER_SR_ROOT"
Rscript training/base/v3/scripts/run.R finalize --run-id "$RIVER_SR_RUN_ID"
