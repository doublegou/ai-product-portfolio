#!/usr/bin/env bash
#SBATCH --job-name=sr_v3_check
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=12G
#SBATCH --time=01:00:00

set -euo pipefail
: "${RIVER_SR_ROOT:?RIVER_SR_ROOT is required}"
: "${RIVER_SR_RUN_ID:?RIVER_SR_RUN_ID is required}"
set +u; source /etc/profile; set -u
module purge; module load R-4.4.3
cd "$RIVER_SR_ROOT"
Rscript training/base/v3/scripts/run.R test
Rscript -e 'source("training/base/v3/R/common.R"); c <- v3_context(); v3_write_run_manifest(c, Sys.getenv("RIVER_SR_RUN_ID"), list(mode="formal", folds_manifest_sha256=v3_sha256(file.path(c$base,"folds","manifest.json"))))'
