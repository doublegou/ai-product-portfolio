# Regional Risk V2 HPC thread handoff

## Boundary

This thread runs the already frozen forward experiment. Do not run `prepare`; do not alter data, Process14, model recipes, seeds, nested threshold selection, weights or Gate targets.

## Sequence

```bash
git pull --ff-only
bash hpc/slurm/regional_risk_v2/run.sh bootstrap
bash hpc/slurm/regional_risk_v2/run.sh check
bash hpc/slurm/regional_risk_v2/run.sh submit regional_risk_v2_YYYYMMDD_r1
bash hpc/slurm/regional_risk_v2/run.sh status regional_risk_v2_YYYYMMDD_r1
```

## Completion contract

- 68 complete tasks: 17 folds for each of four candidates.
- Each task contains 16 inner fits, one inner-only FPR10 threshold and one outer fit; no calibration.
- Total: 1,156 model fits, 68 thresholds and 1,488 outer OOF rows.
- Each candidate covers all 372 rows exactly once.
- `gate_metrics.csv`, `ranking_metrics.csv`, `branch_metrics.csv`, `extreme_audit.csv`, `DECISION.md` and `oof_manifest.json` are present.
- `full_data_model_fitted=false` and `release_created=false`.

Return the archive and checksum to the engineering/conclusion thread:

```bash
bash hpc/slurm/regional_risk_v2/run.sh archive regional_risk_v2_YYYYMMDD_r1
sha256sum --check hpc/transfer/regional_risk_v2_regional_risk_v2_YYYYMMDD_r1.tar.gz.sha256
```
