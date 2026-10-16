#!/bin/bash
#SBATCH --job-name=sr_age_overlay
#SBATCH --partition=batch
#SBATCH --array=0-7%2
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=logs/sr_age_overlay_%A_%a.out
#SBATCH --error=logs/sr_age_overlay_%A_%a.err

set -euo pipefail

cd "${SLURM_SUBMIT_DIR}"

source slurm/common_env.sh

regions=(
  af
  ar
  au
  eu
  gr
  na
  sa
  si
)

region="${regions[$SLURM_ARRAY_TASK_ID]}"

echo "Processing HydroBASINS region: ${region}"

Rscript \
  "R/23_overlay_nrcan_age_to_hydrobasins_${region}.R"
