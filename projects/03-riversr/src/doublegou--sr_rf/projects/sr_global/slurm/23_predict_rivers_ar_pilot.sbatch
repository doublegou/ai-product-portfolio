#!/bin/bash
#SBATCH --job-name=sr_pred_ar
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=24:00:00
#SBATCH --output=logs/sr_pred_ar_%j.out
#SBATCH --error=logs/sr_pred_ar_%j.err

set -euo pipefail

export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global

export PATH=$CONDA_PREFIX/bin:/usr/local/bin:/usr/bin:/bin
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}

PROJ_DB=$(find "$CONDA_PREFIX" \
  -type f -name proj.db -print -quit)

GDAL_MARKER=$(find "$CONDA_PREFIX" \
  -type f \
  \( -name gdalvrt.xsd -o -name header.dxf \) \
  -print -quit)

export PROJ_DATA="$(dirname "$PROJ_DB")"
export PROJ_LIB="$PROJ_DATA"
export GDAL_DATA="$(dirname "$GDAL_MARKER")"

export SR_NTHREADS=$SLURM_CPUS_PER_TASK
export SR_OVERWRITE=0

cd "$SR_GLOBAL_DIR"

mkdir -p logs

/home/zhangmeng/envs/sr_global/bin/Rscript \
  scripts/23_predict_region_rivers_RF_QRF.R \
  ar \
  25000
