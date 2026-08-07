#!/bin/bash
#SBATCH -J test_R_direct
#SBATCH -p batch
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:20:00
#SBATCH --output=logs/test_R_direct_%j.out
#SBATCH --error=logs/test_R_direct_%j.err

cd $SLURM_SUBMIT_DIR

export PATH=/home/zhangmeng/envs/sr_global/bin:/public/software/slurm/slurm-22.05.11/bin:/public/software/slurm/slurm-22.05.11/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
unset R_HOME

echo "Running on:"
hostname

echo "R path:"
which R
which Rscript

echo "Rscript version:"
Rscript --version

Rscript -e "pkgs <- c('terra','sf','raster','data.table','dplyr','ranger','randomForest','caret','future','furrr','arrow','optparse'); print(sapply(pkgs, requireNamespace, quietly=TRUE)); sessionInfo()"
