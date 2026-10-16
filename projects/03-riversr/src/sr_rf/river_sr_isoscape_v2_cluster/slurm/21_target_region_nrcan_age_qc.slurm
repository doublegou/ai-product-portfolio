#!/bin/bash
#SBATCH --job-name=nrcan_age_target
#SBATCH --partition=batch
#SBATCH --cpus-per-task=2
#SBATCH --mem=12G
#SBATCH --time=00:15:00
#SBATCH --output=logs/nrcan_age_target_%j.out
#SBATCH --error=logs/nrcan_age_target_%j.err

set -euo pipefail

cd "${SLURM_SUBMIT_DIR}"

source slurm/common_env.sh

Rscript R/21_target_region_nrcan_age_qc.R
