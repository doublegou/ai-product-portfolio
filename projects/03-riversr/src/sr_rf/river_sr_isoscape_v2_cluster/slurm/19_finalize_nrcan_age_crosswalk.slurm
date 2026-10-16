#!/usr/bin/env bash
#SBATCH --job-name=nrcan_age_final
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:40:00
#SBATCH --output=logs/nrcan_age_final_%j.out
#SBATCH --error=logs/nrcan_age_final_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

mkdir -p \
  logs \
  outputs/nrcan_of5529/final_age_crosswalk

source slurm/common_env.sh

"${ENV_PREFIX}/bin/Rscript" \
  --vanilla \
  R/19_finalize_nrcan_age_crosswalk.R
