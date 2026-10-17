# Archived training artifacts

The repository includes a one-time archival snapshot of the locally retained
training artifacts available on 2026-10-17. This snapshot is intended to make
the completed experiments inspectable from a fresh clone.

## Included

- Base V0-V3 formal and smoke run directories.
- Global high-Sr risk and correction-feasibility runs.
- Regional expert V1, V1.1, and V2 runs.
- Task-level validation outputs, metrics, predictions, reports, run metadata,
  scheduler logs, standard output, and standard error.
- Release model bundles and run-level RDS model snapshots through Git LFS.
- Regional Risk V2 retained fold-level validation results.
- The raw-feature download inventory with source URLs, expected sizes, and
  SHA-256 checksums.

## Intentionally excluded

- Downloaded raw hydrography, climate, geology, soil, and terrain datasets.
- The local R package library under `env/library/`.
- HPC transport archives under `hpc/transfer/`.
- `.codex_tmp/` audits, temporary worktrees, document renders, and duplicate
  working copies.

Raw feature sources can be reconstructed from
`data_pipeline/raw_features/config/sources.yml` and
`data/raw/features/download_inventory.csv`.

## Fresh clone

Install Git LFS before cloning, or run the following after cloning:

```text
git lfs install
git lfs pull
```

The R dependency environment remains reproducible through `env/renv.lock` and
`Rscript env/bootstrap.R`.
