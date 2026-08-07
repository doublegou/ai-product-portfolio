#!/usr/bin/env bash
#SBATCH --job-name=audit_rudbf
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=00:20:00
#SBATCH --output=logs/audit_rudbf_%j.out
#SBATCH --error=logs/audit_rudbf_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

mkdir -p \
  logs \
  outputs/nrcan_of5529/rudbf_audit

source slurm/common_env.sh

"${ENV_PREFIX}/bin/Rscript" \
  R/15_audit_nrcan_rudbf.R
