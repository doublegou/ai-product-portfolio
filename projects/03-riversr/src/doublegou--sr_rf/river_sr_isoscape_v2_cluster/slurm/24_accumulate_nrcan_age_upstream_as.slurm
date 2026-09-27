#!/bin/bash
#SBATCH --job-name=sr_age_as_up
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=00:20:00
#SBATCH --output=logs/sr_age_as_up_%j.out
#SBATCH --error=logs/sr_age_as_up_%j.err

set -euo pipefail

cd "${SLURM_SUBMIT_DIR}"

source slurm/common_env.sh

Rscript R/24_accumulate_nrcan_age_upstream_as.R
