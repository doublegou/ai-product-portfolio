#!/bin/bash
#SBATCH --job-name=nrcan_age_spqc
#SBATCH --partition=batch
#SBATCH --cpus-per-task=2
#SBATCH --mem=24G
#SBATCH --time=00:30:00
#SBATCH --output=logs/nrcan_age_spqc_%j.out
#SBATCH --error=logs/nrcan_age_spqc_%j.err

set -euo pipefail

cd "${SLURM_SUBMIT_DIR}"

source slurm/common_env.sh

Rscript R/20_spatial_qc_nrcan_age.R
