#!/bin/bash
#SBATCH --job-name=sr_gsnap
#SBATCH --partition=batch
#SBATCH --array=0-8
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/sr_gsnap_%A_%a.out
#SBATCH --error=logs/sr_gsnap_%A_%a.err
set -euo pipefail
export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export PATH=/home/zhangmeng/envs/sr_global/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
unset R_HOME
export CONDA_PREFIX=/home/zhangmeng/envs/sr_global
export PROJ_DATA=$CONDA_PREFIX/share/proj
export PROJ_LIB=$CONDA_PREFIX/share/proj
export GDAL_DATA=$CONDA_PREFIX/share/gdal
export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:${LD_LIBRARY_PATH:-}
cd "$SR_GLOBAL_DIR"
mkdir -p logs data_processed/global/snap_by_region outputs/global
regions=(af ar as au eu gr na sa si)
region="${regions[$SLURM_ARRAY_TASK_ID]}"
echo "SLURM array task: $SLURM_ARRAY_TASK_ID"
echo "HydroSHEDS region: $region"
/home/zhangmeng/envs/sr_global/bin/Rscript scripts/02_snap_region_hydrorivers.R "$region"
