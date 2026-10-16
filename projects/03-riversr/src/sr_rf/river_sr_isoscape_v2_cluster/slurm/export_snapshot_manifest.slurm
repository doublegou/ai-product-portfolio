#!/bin/bash
#SBATCH --job-name=sr_export_manifest
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=04:00:00
#SBATCH --output=/home/zhangmeng/river_sr_exports/logs/export_manifest_%j.out
#SBATCH --error=/home/zhangmeng/river_sr_exports/logs/export_manifest_%j.err

set -euo pipefail

PROJECT="/home/zhangmeng/river_sr_isoscape_v2_cluster"
LEGACY="/home/zhangmeng/projects/sr_global"
ENV_PREFIX="/home/zhangmeng/.local/share/mamba/envs/sr_rf"
RSCRIPT="${ENV_PREFIX}/bin/Rscript"

STAMP=$(
  date '+%Y%m%d_%H%M%S'
)

META_ROOT="${PROJECT}/outputs/export_manifest"
META_DIR="${META_ROOT}/${STAMP}"

mkdir -p \
  "${META_DIR}"

printf '%s\n' "${STAMP}" \
  > "${META_ROOT}/LATEST.txt"

cat > "${META_DIR}/README_EXPORT_MANIFEST.txt" <<EOF
GLOBAL RIVER WATER 87Sr/86Sr ISOSCAPE EXPORT MANIFEST
=====================================================

Created:
$(date --iso-8601=seconds)

Primary project:
/home/zhangmeng/river_sr_isoscape_v2_cluster

Legacy dependency project:
/home/zhangmeng/projects/sr_global

R environment:
/home/zhangmeng/.local/share/mamba/envs/sr_rf

The primary project and legacy dependency project must both be
downloaded to preserve the currently used code, results and
deployment assets.

The binary micromamba environment is not copied. Package and
environment manifests are recorded in this directory instead.
EOF

{
  echo "===== DATE ====="
  date --iso-8601=seconds

  echo
  echo "===== HOST ====="
  hostname

  echo
  echo "===== KERNEL ====="
  uname -a

  echo
  echo "===== PROJECT SIZE ====="
  du -sh "${PROJECT}"
  du -sb "${PROJECT}"

  echo
  echo "===== LEGACY SIZE ====="
  du -sh "${LEGACY}"
  du -sb "${LEGACY}"

  echo
  echo "===== FILESYSTEM ====="
  df -h "${PROJECT}"
  df -h "${LEGACY}"

  echo
  echo "===== QUOTA ====="
  quota -s 2>/dev/null || true
} > "${META_DIR}/storage_and_system_summary.txt"

squeue \
  -u "$USER" \
  -o '%.18i %.32j %.10T %.10M %.6D %R' \
  > "${META_DIR}/squeue_snapshot.txt" \
  2>&1 \
  || true

sacct \
  -u "$USER" \
  -S 2026-07-01 \
  --format=JobID,JobName%32,State,ExitCode,Elapsed,MaxRSS,Submit,Start,End \
  > "${META_DIR}/slurm_accounting_since_20260701.txt" \
  2>&1 \
  || true

find "${PROJECT}" \
  -xdev \
  -printf '%y\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\t%p\n' \
  | LC_ALL=C sort \
  > "${META_DIR}/project_file_inventory.tsv"

find "${LEGACY}" \
  -xdev \
  -printf '%y\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\t%p\n' \
  | LC_ALL=C sort \
  > "${META_DIR}/legacy_file_inventory.tsv"

find "${PROJECT}" \
  -type l \
  -printf '%p\t%l\n' \
  | LC_ALL=C sort \
  > "${META_DIR}/project_symlink_inventory.tsv"

find "${LEGACY}" \
  -type l \
  -printf '%p\t%l\n' \
  | LC_ALL=C sort \
  > "${META_DIR}/legacy_symlink_inventory.tsv"

{
  find \
    "${PROJECT}/R" \
    "${PROJECT}/slurm" \
    -type f \
    -print0 \
    2>/dev/null \
    | LC_ALL=C sort -z \
    | xargs -0 -r sha256sum
} > "${META_DIR}/code_sha256.txt"

grep \
  -RInE \
  --include='*.R' \
  --include='*.r' \
  --include='*.sh' \
  --include='*.slurm' \
  --include='*.py' \
  '/home/zhangmeng/' \
  "${PROJECT}/R" \
  "${PROJECT}/slurm" \
  2>/dev/null \
  > "${META_DIR}/absolute_path_references.txt" \
  || true

{
  find \
    "${PROJECT}/outputs" \
    -type f \
    -name 'run_summary.txt' \
    -print0 \
    2>/dev/null \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' summary_file; do
        echo
        echo "============================================================"
        echo "${summary_file}"
        echo "============================================================"
        cat "${summary_file}"
      done
} > "${META_DIR}/all_run_summaries.txt"

{
  echo "===== PROJECT TOP LEVEL ====="
  find "${PROJECT}" \
    -mindepth 1 \
    -maxdepth 1 \
    -printf '%y\t%f\n' \
    | LC_ALL=C sort

  echo
  echo "===== PROJECT DIRECTORY SIZES ====="
  du \
    -sh \
    "${PROJECT}"/* \
    "${PROJECT}"/.[!.]* \
    2>/dev/null \
    | sort -h

  echo
  echo "===== LEGACY DIRECTORY SIZES ====="
  du \
    -sh \
    "${LEGACY}"/* \
    "${LEGACY}"/.[!.]* \
    2>/dev/null \
    | sort -h
} > "${META_DIR}/directory_size_inventory.txt"

if [ -d "${PROJECT}/.git" ]; then
  git \
    -C "${PROJECT}" \
    status \
    --short \
    > "${META_DIR}/git_status.txt" \
    2>&1 \
    || true

  git \
    -C "${PROJECT}" \
    log \
    --oneline \
    --decorate \
    --all \
    -n 100 \
    > "${META_DIR}/git_log_last_100.txt" \
    2>&1 \
    || true

  git \
    -C "${PROJECT}" \
    diff \
    > "${META_DIR}/git_uncommitted_diff.patch" \
    2>&1 \
    || true
fi

META_DIR="${META_DIR}" \
"${RSCRIPT}" \
  --vanilla \
  -e '
    output_dir <- Sys.getenv("META_DIR")

    writeLines(
      capture.output(sessionInfo()),
      file.path(
        output_dir,
        "R_sessionInfo.txt"
      )
    )

    packages <- as.data.frame(
      installed.packages()[
        ,
        c(
          "Package",
          "Version",
          "LibPath"
        ),
        drop = FALSE
      ]
    )

    write.csv(
      packages,
      file.path(
        output_dir,
        "R_installed_packages.csv"
      ),
      row.names = FALSE
    )
  '

if command -v micromamba >/dev/null 2>&1; then
  micromamba \
    list \
    -p "${ENV_PREFIX}" \
    > "${META_DIR}/micromamba_package_list.txt" \
    2>&1 \
    || true

  micromamba \
    list \
    -p "${ENV_PREFIX}" \
    --explicit \
    > "${META_DIR}/micromamba_explicit.txt" \
    2>&1 \
    || true
else
  echo "micromamba command was not available in PATH." \
    > "${META_DIR}/micromamba_package_list.txt"

  find \
    "${ENV_PREFIX}/conda-meta" \
    -maxdepth 1 \
    -type f \
    -printf '%f\n' \
    2>/dev/null \
    | LC_ALL=C sort \
    > "${META_DIR}/conda_meta_file_list.txt" \
    || true
fi

if [ -x "${ENV_PREFIX}/bin/python" ]; then
  "${ENV_PREFIX}/bin/python" \
    --version \
    > "${META_DIR}/python_version.txt" \
    2>&1 \
    || true

  "${ENV_PREFIX}/bin/python" \
    -m pip \
    freeze \
    > "${META_DIR}/python_pip_freeze.txt" \
    2>&1 \
    || true
fi

{
  echo "Project files:"
  find "${PROJECT}" \
    -xdev \
    -type f \
    | wc -l

  echo
  echo "Project directories:"
  find "${PROJECT}" \
    -xdev \
    -type d \
    | wc -l

  echo
  echo "Legacy files:"
  find "${LEGACY}" \
    -xdev \
    -type f \
    | wc -l

  echo
  echo "Legacy directories:"
  find "${LEGACY}" \
    -xdev \
    -type d \
    | wc -l
} > "${META_DIR}/file_and_directory_counts.txt"

cat > "${META_DIR}/run_summary.txt" <<EOF
SR PROJECT EXPORT MANIFEST
==========================

Manifest timestamp: ${STAMP}

Primary project:
${PROJECT}

Legacy dependency:
${LEGACY}

Manifest directory:
${META_DIR}

Project and legacy file inventories: CREATED
Code SHA256 manifest: CREATED
Symlink inventories: CREATED
Absolute path reference audit: CREATED
Combined run summaries: CREATED
R environment manifest: CREATED
Slurm accounting snapshot: CREATED

STATUS: EXPORT MANIFEST PASSED
EOF

cat "${META_DIR}/run_summary.txt"
