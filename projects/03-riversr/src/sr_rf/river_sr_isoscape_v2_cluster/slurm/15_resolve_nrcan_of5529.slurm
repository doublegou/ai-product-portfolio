#!/usr/bin/env bash
#SBATCH --job-name=resolve_of5529
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:10:00
#SBATCH --output=logs/resolve_of5529_%j.out
#SBATCH --error=logs/resolve_of5529_%j.err

set -euo pipefail

cd "${HOME}/river_sr_isoscape_v2_cluster"

mkdir -p \
  logs \
  data/raw/geology/nrcan_of5529 \
  outputs/nrcan_of5529

bash scripts/15_resolve_nrcan_of5529.sh
