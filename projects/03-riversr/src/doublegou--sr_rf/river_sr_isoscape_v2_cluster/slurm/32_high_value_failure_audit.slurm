#!/usr/bin/env bash

#SBATCH --job-name=sr_high_audit
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH --output=logs/sr_high_audit_%j.out
#SBATCH --error=logs/sr_high_audit_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

source slurm/common_env.sh

R_SCRIPT="${HOME}/river_sr_isoscape_v2_cluster/R/32_high_value_failure_audit.R"
R_BIN="/home/zhangmeng/.local/share/mamba/envs/sr_rf/bin/Rscript"

echo "Project directory: $(pwd)"
echo "Rscript: ${R_BIN}"
echo "Audit script: ${R_SCRIPT}"

"${R_BIN}" "${R_SCRIPT}"
