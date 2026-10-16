#!/bin/bash
#SBATCH --job-name=sr_age_as_overlay
#SBATCH --partition=batch
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=logs/sr_age_as_overlay_%j.out
#SBATCH --error=logs/sr_age_as_overlay_%j.err

set -euo pipefail

cd "${SLURM_SUBMIT_DIR}"

source slurm/common_env.sh

Rscript R/23_overlay_nrcan_age_to_hydrobasins_as.R
