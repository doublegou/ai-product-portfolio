#!/bin/bash
#SBATCH --job-name=sr_rasterize
#SBATCH --output=logs/30_rasterize_%j.out
#SBATCH --error=logs/30_rasterize_%j.err
#SBATCH --time=02:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=4

set -euo pipefail

cd /home/zhangmeng/projects/sr_global

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/30_rasterize_global_river_sr_maps.R
