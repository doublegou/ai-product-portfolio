#!/bin/bash
#SBATCH -J model1_2_all
#SBATCH -p batch
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=05:00:00
#SBATCH --output=logs/model1_2_all_%j.out
#SBATCH --error=logs/model1_2_all_%j.err

cd $SLURM_SUBMIT_DIR

export PATH=/home/zhangmeng/envs/sr_global/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
unset R_HOME
hash -r

export SR_SITE_DIR=/home/zhangmeng/projects/sr_global
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

Rscript scripts/01_filter_solute_and_pilot_points.R
Rscript scripts/02_model1_2_spatial_hydro_baselines.R
