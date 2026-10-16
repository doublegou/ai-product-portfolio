#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f data/external/predictors_at_sites.rds ]]; then
  echo "Missing data/external/predictors_at_sites.rds" >&2
  echo "Run only QC first: bash slurm/submit_qc.sh" >&2
  echo "Then build predictors using data/external/predictors_at_sites_TEMPLATE.csv." >&2
  exit 2
fi

j0=$(sbatch --parsable slurm/00_qc.slurm)
j1=$(sbatch --parsable --dependency=afterok:$j0 slurm/01_model_table.slurm)
j2=$(sbatch --parsable --dependency=afterok:$j1 slurm/02_folds.slurm)
j3=$(sbatch --parsable --dependency=afterok:$j2 slurm/03_experiment_A.slurm)
j4=$(sbatch --parsable --dependency=afterok:$j3 slurm/04_experiment_B.slurm)
j5=$(sbatch --parsable --dependency=afterok:$j4 slurm/05_diagnose.slurm)
j6=$(sbatch --parsable --dependency=afterok:$j5 slurm/06_experiment_C.slurm)
echo "Submitted jobs: QC=$j0 table=$j1 folds=$j2 A=$j3 B=$j4 diagnose=$j5 C=$j6"
echo "D, E and final are intentionally not auto-submitted because they require external regime/weighting/prediction inputs."
