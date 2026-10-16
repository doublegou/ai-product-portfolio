#!/usr/bin/env bash
#SBATCH --job-name=sr_table
#SBATCH --partition=batch
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

source slurm/common_env.sh
Rscript R/99_run_stage.R table
