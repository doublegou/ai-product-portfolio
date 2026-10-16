#!/bin/bash
#SBATCH -J test_hpc
#SBATCH -p batch
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:10:00
#SBATCH --output=logs/test_hpc_%j.out
#SBATCH --error=logs/test_hpc_%j.err

cd $SLURM_SUBMIT_DIR

echo "Job starts at:"
date
echo "Running on:"
hostname
echo "Current directory:"
pwd
echo "CPU info:"
nproc
echo "Job ends at:"
date
