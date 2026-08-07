#!/usr/bin/env bash
#SBATCH --job-name=nrcan_age_xw
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:20:00
#SBATCH --output=logs/nrcan_age_xw_%j.out
#SBATCH --error=logs/nrcan_age_xw_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

mkdir -p \
  logs \
  outputs/nrcan_of5529/age_crosswalk

source slurm/common_env.sh

"${ENV_PREFIX}/bin/Rscript" \
  --vanilla \
  R/16_build_nrcan_age_crosswalk.R
