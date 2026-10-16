#!/bin/bash
#SBATCH --job-name=sr_joinclim
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --output=logs/sr_joinclim_%j.out
#SBATCH --error=logs/sr_joinclim_%j.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

unset R_HOME

cd "$SR_GLOBAL_DIR"

mkdir -p \
  logs \
  outputs/global/climate_terrain_site_qc

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/12_attach_l6_climate_terrain_to_sites.R
