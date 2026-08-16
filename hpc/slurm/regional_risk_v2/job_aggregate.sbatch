#!/usr/bin/env bash
#SBATCH --job-name=sr_rrisk2_aggregate
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
set -euo pipefail
: "${RIVER_SR_ROOT:?RIVER_SR_ROOT is required}"
: "${RIVER_SR_RUN_ID:?RIVER_SR_RUN_ID is required}"
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
set +u; source /etc/profile; set -u
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
module purge; module load R-4.4.3
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
cd "$RIVER_SR_ROOT"
Rscript training/regional_expert/regional_risk_v2/scripts/run.R --stage aggregate --run-id "$RIVER_SR_RUN_ID"
Rscript training/regional_expert/regional_risk_v2/scripts/run.R --stage summarize --run-id "$RIVER_SR_RUN_ID"
