#!/bin/bash
#SBATCH --job-name=p0_full1500
#SBATCH --partition=batch
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/p0_full1500_%j.out
#SBATCH --error=logs/p0_full1500_%j.err

set -euo pipefail

cd "$HOME/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript \
  R/38_experiment_p0_full_range_1500.R
