#!/usr/bin/env bash
#SBATCH --job-name=sr_v3_env
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=04:00:00

set -euo pipefail
: "${RIVER_SR_ROOT:?RIVER_SR_ROOT is required}"
set +u; source /etc/profile; set -u
module purge
module load R-4.4.3
cd "$RIVER_SR_ROOT"
Rscript env/bootstrap.R
Rscript -e 'source("env/activate.R"); river_sr_activate(getwd()); p <- c("yaml","jsonlite","digest","data.table","foreign","sf","ranger","xgboost"); stopifnot(all(vapply(p, requireNamespace, logical(1), quietly=TRUE))); print(sessionInfo())'
