#!/usr/bin/env bash
#SBATCH --job-name=sr_risk_rf
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=24G
#SBATCH --time=12:00:00

set -euo pipefail
: "${RIVER_SR_ROOT:?RIVER_SR_ROOT is required}"
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
set +u; source /etc/profile; set -u
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
module purge
module load R-4.4.3
unset R_HOME R_LIBS R_LIBS_USER R_LIBS_SITE
cd "$RIVER_SR_ROOT"
task_id=$(( ${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is required} + 16 ))
Rscript training/global_correction/global_high_sr_risk/scripts/run.R --task-id "$task_id" --force
