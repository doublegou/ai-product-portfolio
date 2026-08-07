#!/bin/bash
#SBATCH --job-name=m1_existing
#SBATCH --partition=batch
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/m1_existing_%j.out
#SBATCH --error=logs/m1_existing_%j.err

set -euo pipefail

cd ~/river_sr_isoscape_v2_cluster

mkdir -p logs

source slurm/common_env.sh

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  R/44_experiment_m1_existing_modules.R
