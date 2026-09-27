#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/river_sr_isoscape_v2_cluster}"
ENV_NAME="${ENV_NAME:-sr_rf}"

cd "$PROJECT_DIR"

MAMBA_EXE="$(command -v micromamba || true)"

if [[ -z "$MAMBA_EXE" ]]; then
    echo "ERROR: micromamba was not found." >&2
    exit 1
fi

ENV_PREFIX="$(
    "$MAMBA_EXE" env list |
    awk -v env="$ENV_NAME" '$1 == env {print $NF; exit}'
)"

if [[ -z "$ENV_PREFIX" || ! -d "$ENV_PREFIX" ]]; then
    echo "ERROR: micromamba environment '$ENV_NAME' was not found." >&2
    "$MAMBA_EXE" env list >&2
    exit 1
fi

if [[ ! -x "$ENV_PREFIX/bin/Rscript" ]]; then
    echo "ERROR: Rscript was not found in $ENV_PREFIX/bin" >&2
    exit 1
fi

export PATH="$ENV_PREFIX/bin:$PATH"
export RIVER_SR_PROJECT_ROOT="$PROJECT_DIR"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"
export OPENBLAS_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK:-4}"

echo "Project directory: $PROJECT_DIR"
echo "Environment prefix: $ENV_PREFIX"
echo "Rscript: $(command -v Rscript)"

# ---- PROJ / GDAL runtime configuration ----
unset PROJ_DATABASE_PATH

export PROJ_DATA="${ENV_PREFIX}/share/proj"
export PROJ_LIB="${ENV_PREFIX}/share/proj"
export GDAL_DATA="${ENV_PREFIX}/share/gdal"
export PROJ_NETWORK="OFF"

if [[ ! -f "${PROJ_DATA}/proj.db" ]]; then
  echo "Missing PROJ database: ${PROJ_DATA}/proj.db" >&2
  exit 1
fi
