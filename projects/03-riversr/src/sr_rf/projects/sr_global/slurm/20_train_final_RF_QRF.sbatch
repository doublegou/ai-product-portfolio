#!/bin/bash
#SBATCH --job-name=sr_final_qrf
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/sr_final_qrf_%j.out
#SBATCH --error=logs/sr_final_qrf_%j.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/usr/local/bin:/usr/bin:/bin
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

export PROJ_DATA=$CONDA_PREFIX/share/proj
export PROJ_LIB=$CONDA_PREFIX/share/proj
export GDAL_DATA=$CONDA_PREFIX/share/gdal

export SR_NTHREADS=$SLURM_CPUS_PER_TASK

cd "$SR_GLOBAL_DIR"

mkdir -p \
  logs \
  outputs/global/final_RF_QRF \
  models/global/final_RF_QRF

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/20_train_final_RF_QRF.R
