#!/bin/bash
#SBATCH --job-name=sr_age_stop
#SBATCH --partition=batch
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=logs/sr_age_stop_%j.out
#SBATCH --error=logs/sr_age_stop_%j.err

set -euo pipefail

cd "${SLURM_SUBMIT_DIR}"

source slurm/common_env.sh

Rscript \
  R/31_experiment_age_stop_test.R
