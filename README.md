# sr_rf

Reproducible local and cluster environment for the river-water Sr modeling code.

## Bootstrap

```bash
./bootstrap.sh
```

The script creates a Conda environment named `sr_rf`, restores the R packages
recorded in `river_sr_isoscape_v2_cluster/renv.lock`, and runs a software-only
environment check. It does not require the training data.

Runtime binaries and installed R packages are deliberately stored outside this
Git repository:

- Conda environment: `<miniforge-or-mamba-root>/envs/sr_rf`
- Project R library: `$CONDA_PREFIX/renv-library/sr_rf`
- renv download cache: the platform's standard user cache

All files created inside this repository are intended to be versioned. No
`.gitignore` is required by the environment bootstrap.

