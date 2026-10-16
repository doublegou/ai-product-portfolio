#!/usr/bin/env bash
#SBATCH --job-name=sr_risk_v1_env
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=03:00:00

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
Rscript env/bootstrap.R
Rscript -e 'source("env/activate.R"); river_sr_activate(getwd()); packages <- c("yaml", "jsonlite", "digest", "data.table", "glmnet", "ranger", "PRROC", "pROC"); stopifnot(all(vapply(packages, requireNamespace, logical(1), quietly = TRUE))); print(sessionInfo())'
