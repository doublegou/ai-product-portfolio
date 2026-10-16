#!/usr/bin/env bash
#SBATCH --job-name=sr_expC
#SBATCH --partition=batch
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=48:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

source slurm/common_env.sh
Rscript R/99_run_stage.R C
