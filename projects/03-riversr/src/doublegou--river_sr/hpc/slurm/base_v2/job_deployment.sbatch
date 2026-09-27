#!/usr/bin/env bash
#SBATCH --job-name=sr_v2_deploy
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=24G
#SBATCH --time=04:00:00

set -euo pipefail
: "${RIVER_SR_ROOT:?RIVER_SR_ROOT is required}"
: "${RIVER_SR_RUN_ID:?RIVER_SR_RUN_ID is required}"
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
set +u; source /etc/profile; set -u
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
module purge
module load R-4.4.3
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
cd "$RIVER_SR_ROOT"
Rscript training/base/v2/scripts/run.R --stage deployment --run-id "$RIVER_SR_RUN_ID" --force
