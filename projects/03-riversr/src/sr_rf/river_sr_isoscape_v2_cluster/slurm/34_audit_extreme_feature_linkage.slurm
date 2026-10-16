#!/usr/bin/env bash

#SBATCH --job-name=sr_link_audit
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:10:00
#SBATCH --output=logs/sr_link_audit_%j.out
#SBATCH --error=logs/sr_link_audit_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

R_BIN="/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript"

"${R_BIN}" \
  R/34_audit_extreme_feature_linkage.R
