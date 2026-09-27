#!/usr/bin/env bash
#SBATCH --job-name=sr_p0_smoke
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=logs/sr_p0_smoke_%j.out
#SBATCH --error=logs/sr_p0_smoke_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

Rscript R/03_p0_smoke_test.R
