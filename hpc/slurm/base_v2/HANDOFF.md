# Base V2 HPC handoff

## Preconditions already completed locally

- HydroBASINS L12 acquired and verified.
- Response-blind HydroRIVERS station-frontier topology reconstruction completed for exactly 4,485 Full50 stations.
- Frozen Primary geometry is 221 branches / 2,577 eligible rows; every branch contains at most 19 stations.
- Primary selected automatically from topology-only Small/Primary/Large diagnostics.
- `training/base/v2/folds/fold_manifest.json` status is `FOLDS_FROZEN_BEFORE_RESPONSE_EVALUATION`.
- Local engineering check passes.
- No Base V2 RF has been trained locally.

## Cluster procedure

1. Pull the committed repository state.
2. Confirm `data/processed/training/sr_full50_v1.csv` is present with the frozen hash.
3. Do not upload raw GIS or `data/interim/`; formal training needs only the Full50 table, V2 code/config and frozen folds.
4. Bootstrap the locked R environment if required.
5. Submit one named full run through `hpc/slurm/base_v2/run.sh`.
6. Monitor the five-stage dependency chain and do not manually bypass a failed check or task.
7. Archive the completed folds, validation and run directory; verify SHA-256 before local extraction.
8. Do not run `--stage release` until the returned scientific report and integrity checks have been reviewed.

Use a new run ID. The earlier `base_v2_full_20260817_r1` run belongs to the superseded Pfaf-prefix branch geometry and is not an input to this workflow.

## Expected formal workload

- Primary: 15 tasks, each 48 x 500-tree coarse, best 16 x 1,000-tree refinement, then a 2,000-tree Outer fit.
- Deployment: 48 recipes x 5 Purged-Branch folds x 2,000 trees.
- Stress: 25 fixed-recipe tasks covering terminal, spatial 500/1,000/1,500 km and reference grouped designs.
- Finalize: aggregate all OOF evidence and fit one Full50 4,000-tree final model on 4,485 rows.

No smoke training is part of this workflow.
