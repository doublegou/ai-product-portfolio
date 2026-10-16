#!/usr/bin/env bash
#SBATCH --job-name=macrostrat_save
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=logs/macrostrat_save_%j.out
#SBATCH --error=logs/macrostrat_save_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

mkdir -p \
  logs \
  outputs/macrostrat_map_audit

"${ENV_PREFIX}/bin/Rscript" \
  R/13_save_macrostrat_audit_unit.R
