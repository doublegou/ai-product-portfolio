#!/bin/bash
#SBATCH -J m12_step1
#SBATCH -p batch
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=01:00:00
#SBATCH --output=logs/m12_step1_%j.out
#SBATCH --error=logs/m12_step1_%j.err

cd $SLURM_SUBMIT_DIR

export PATH=/home/zhangmeng/envs/sr_global/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
unset R_HOME
hash -r

export SR_SITE_DIR=/home/zhangmeng/projects/sr_global
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

Rscript scripts/01_filter_solute_and_pilot_points.R
