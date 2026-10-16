#!/bin/bash
#SBATCH --job-name=sr_soilprep
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=logs/sr_soilprep_%j.out
#SBATCH --error=logs/sr_soilprep_%j.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

unset R_HOME

export PROJ_DATA=$CONDA_PREFIX/share/proj
export PROJ_LIB=$CONDA_PREFIX/share/proj
export GDAL_DATA=$CONDA_PREFIX/share/gdal
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export GDAL_NUM_THREADS=$SLURM_CPUS_PER_TASK

cd "$SR_GLOBAL_DIR"

mkdir -p \
  logs \
  data_processed/global/soil_5000m \
  outputs/global/soil_5000m_qc \
  tmp/terra_soil

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/15_prepare_soilgrids_0_30cm.R
