#!/bin/bash
#SBATCH --job-name=r46b_lith_diag
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:15:00
#SBATCH --output=logs/r46b_lith_diag_%j.out
#SBATCH --error=logs/r46b_lith_diag_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

mkdir -p logs

source slurm/common_env.sh

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  R/46b_diagnose_local_lithology_mismatches.R
