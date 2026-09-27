#!/usr/bin/env bash
#SBATCH --job-name=source154_legend
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=logs/source154_legend_%j.out
#SBATCH --error=logs/source154_legend_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

mkdir -p \
  logs \
  data/processed/geology \
  outputs/macrostrat_source_154

"${ENV_PREFIX}/bin/Rscript" \
  R/14_prepare_macrostrat_source154_legend.R
