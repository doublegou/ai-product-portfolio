#!/bin/bash
#SBATCH --job-name=r45_asset_audit
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=12G
#SBATCH --time=01:00:00
#SBATCH --output=logs/r45_asset_audit_%j.out
#SBATCH --error=logs/r45_asset_audit_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

mkdir -p logs

source slurm/common_env.sh

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  R/45_audit_local_geology_terrain_assets.R
