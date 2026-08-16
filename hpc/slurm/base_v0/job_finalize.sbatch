#!/usr/bin/env bash
#SBATCH --job-name=sr_v0_finalize
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=16G
#SBATCH --time=01:00:00

set -euo pipefail

: "${RIVER_SR_ROOT:?RIVER_SR_ROOT is required}"
: "${RIVER_SR_RUN_ID:?RIVER_SR_RUN_ID is required}"

module purge
module load R-4.4.3
cd "$RIVER_SR_ROOT"

Rscript training/base/v0/scripts/run.R \
  --mode full \
  --run-id "$RIVER_SR_RUN_ID"
