#!/bin/bash
#SBATCH --job-name=r46_local_lith
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=16G
#SBATCH --time=01:30:00
#SBATCH --output=logs/r46_local_lith_%j.out
#SBATCH --error=logs/r46_local_lith_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

mkdir -p logs

source slurm/common_env.sh

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  R/46_audit_full_range_local_lithology_compatibility.R
