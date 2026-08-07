#!/bin/bash
#SBATCH --job-name=sr_global_merge
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=48G
#SBATCH --time=04:00:00
#SBATCH --output=logs/sr_global_merge_%j.out
#SBATCH --error=logs/sr_global_merge_%j.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/usr/local/bin:/usr/bin:/bin
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

cd "$SR_GLOBAL_DIR"

mkdir -p logs

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/25_combine_global_river_predictions.R
