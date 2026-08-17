# Base V3 — 5,600-site global model competition

Base V3 is the formal implementation of the 5,600-site Random Forest versus
XGBoost global continuous-regression experiment.

## Layout

- `config/`: frozen scientific and runtime configuration.
- `folds/`: immutable site, hydrological, Inner/Outer and stress assignments.
- `R/`: reusable implementation functions.
- `scripts/`: command-line stage entry points.
- `validation/`: canonical summaries copied from a completed formal run.
- `release/`: final approved model bundle and metadata.
- `runs/<run_id>/`: resumable task outputs, logs, reports and model objects.

## Formal workflow

```text
prepare -> 15 RF primary + 15 XGB primary -> aggregate primary
        -> deployment tuning (RF and XGB)
        -> 20 RF stress + 20 XGB stress
        -> final full-data fits -> check/release
```

Run locally from the repository root:

```bash
Rscript training/base/v3/scripts/run.R prepare
Rscript training/base/v3/scripts/run.R smoke --run-id local_smoke
```

The complete experiment is intended for Slurm. See `hpc/slurm/base_v3/`.
Every formal stage requires an explicit `run_id`; outputs are checkpointed and
never silently reused across run IDs.

## Non-negotiable contracts

- Input is `data/processed/training/sr_full50_v2.csv` with 5,600 rows and the
  frozen 50-predictor manifest.
- Hydrological isolation uses HydroBASINS level-6 `MAIN_BAS`, mapped and frozen
  before fitting. A system never crosses an Inner or Outer split.
- All data-derived preprocessing is fitted inside the current analysis split.
- Weight scheme is tuned inside Inner CV; assessment metrics are unweighted.
- Outer test rows are touched once after a candidate is frozen.
- Stress folds never tune a model.
See `SCIENTIFIC_DESIGN.md` and `IMPLEMENTATION_DECISIONS.md` for the complete
scientific and engineering contracts.
