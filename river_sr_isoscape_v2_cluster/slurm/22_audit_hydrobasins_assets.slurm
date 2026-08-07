#!/bin/bash
#SBATCH --job-name=sr_hybas_audit
#SBATCH --partition=batch
#SBATCH --cpus-per-task=2
#SBATCH --mem=32G
#SBATCH --time=00:30:00
#SBATCH --output=logs/sr_hybas_audit_%j.out
#SBATCH --error=logs/sr_hybas_audit_%j.err

set -euo pipefail

cd "${SLURM_SUBMIT_DIR}"

source slurm/common_env.sh

Rscript R/22_audit_hydrobasins_assets.R
