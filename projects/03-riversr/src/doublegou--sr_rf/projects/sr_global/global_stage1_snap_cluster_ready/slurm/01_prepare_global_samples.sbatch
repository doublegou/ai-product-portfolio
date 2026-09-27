#!/bin/bash
#SBATCH --job-name=sr_gprep
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/sr_gprep_%j.out
#SBATCH --error=logs/sr_gprep_%j.err
set -euo pipefail
export SR_GLOBAL_DIR=/home/zhangmeng/projects/sr_global
export PATH=/home/zhangmeng/envs/sr_global/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
unset R_HOME
cd "$SR_GLOBAL_DIR"
mkdir -p logs data_processed/global outputs/global
/home/zhangmeng/envs/sr_global/bin/Rscript scripts/01_prepare_global_samples.R
