#!/usr/bin/env bash
#SBATCH --job-name=sr_expB
#SBATCH --partition=batch
#SBATCH --cpus-per-task=24
#SBATCH --mem=128G
#SBATCH --time=72:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

source slurm/common_env.sh
Rscript R/99_run_stage.R B
