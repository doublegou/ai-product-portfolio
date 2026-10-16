#!/bin/bash
#SBATCH -J test_R_conda
#SBATCH -p batch
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:20:00
#SBATCH --output=logs/test_R_conda_%j.out
#SBATCH --error=logs/test_R_conda_%j.err

cd $SLURM_SUBMIT_DIR

module purge
module load anaconda3
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate /home/zhangmeng/envs/sr_global

unset R_HOME

echo "Running on:"
hostname

echo "R path:"
which R
which Rscript

echo "Rscript version:"
Rscript --version

Rscript -e "pkgs <- c('terra','sf','raster','data.table','dplyr','ranger','randomForest','caret','future','furrr','arrow','optparse'); print(sapply(pkgs, requireNamespace, quietly=TRUE)); sessionInfo()"
