#!/bin/bash
#SBATCH --job-name=sr_mentor_report
#SBATCH --output=logs/29_mentor_report_%j.out
#SBATCH --error=logs/29_mentor_report_%j.err
#SBATCH --time=02:00:00
#SBATCH --mem=24G
#SBATCH --cpus-per-task=2

set -euo pipefail

cd /home/zhangmeng/projects/sr_global

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/29_make_mentor_report_materials.R
