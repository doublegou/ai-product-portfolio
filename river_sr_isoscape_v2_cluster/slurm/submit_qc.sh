#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
jid=$(sbatch --parsable slurm/00_qc.slurm)
echo "Submitted QC job: $jid"
