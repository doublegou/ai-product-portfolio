#!/usr/bin/env bash
#SBATCH --job-name=sr_qc
#SBATCH --partition=batch
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

source slurm/common_env.sh
Rscript R/99_run_stage.R qc
