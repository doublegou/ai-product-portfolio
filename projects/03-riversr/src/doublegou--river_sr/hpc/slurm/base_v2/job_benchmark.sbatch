#!/usr/bin/env bash
#SBATCH --job-name=sr_v2_benchmark
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=16G
#SBATCH --time=02:00:00

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
task_index="${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is required}"
task_id=$((task_index + 1))
Rscript training/base/v2/scripts/run.R --task-type benchmark --task-id "$task_id" --force
