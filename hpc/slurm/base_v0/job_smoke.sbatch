#!/usr/bin/env bash
#SBATCH --job-name=sr_v0_smoke
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=12G
#SBATCH --time=00:30:00

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
cd "$RIVER_SR_ROOT"

Rscript training/base/v0/scripts/run.R \
  --mode smoke \
  --run-id "$RIVER_SR_RUN_ID"
