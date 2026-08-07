#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="${REPO_ROOT}/river_sr_isoscape_v2_cluster"
ENV_SPEC="${PROJECT_DIR}/environment.yml"
ENV_NAME="sr_rf"

platform_id() {
  local kernel machine
  kernel="$(uname -s)"
  machine="$(uname -m)"

  case "${kernel}:${machine}" in
    Darwin:arm64) echo "osx-arm64" ;;
    Darwin:x86_64) echo "osx-64" ;;
    Linux:x86_64) echo "linux-64" ;;
    Linux:aarch64|Linux:arm64) echo "linux-aarch64" ;;
    *)
      echo "Unsupported platform: ${kernel} ${machine}" >&2
      return 1
      ;;
  esac
}

find_environment_manager() {
  local candidate
  for candidate in mamba micromamba conda; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done
  return 1
}

install_micromamba() {
  local platform runtime_root bin_dir temp_dir archive_url
  platform="$(platform_id)"
  runtime_root="${XDG_CACHE_HOME:-${HOME}/.cache}/sr_rf/bootstrap"
  bin_dir="${runtime_root}/bin"
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sr-rf-micromamba.XXXXXX")"
  archive_url="https://micro.mamba.pm/api/micromamba/${platform}/latest"

  mkdir -p "${bin_dir}"
  trap 'rm -rf "${temp_dir}"' RETURN

  echo "No Conda-compatible manager found; downloading micromamba for ${platform}." >&2
  curl --fail --location --silent --show-error "${archive_url}" \
    | tar -xj -C "${temp_dir}" bin/micromamba
  install -m 0755 "${temp_dir}/bin/micromamba" "${bin_dir}/micromamba"
  echo "${bin_dir}/micromamba"
}

environment_exists() {
  "${ENV_MANAGER}" run --name "${ENV_NAME}" Rscript --version >/dev/null 2>&1
}

create_environment() {
  local lock_file manager_name
  lock_file="${REPO_ROOT}/locks/conda-$(platform_id).lock"
  manager_name="$(basename "${ENV_MANAGER}")"

  if [[ -f "${lock_file}" ]]; then
    echo "Creating ${ENV_NAME} from ${lock_file}."
    "${ENV_MANAGER}" create --yes --name "${ENV_NAME}" --file "${lock_file}"
  elif [[ "${manager_name}" == "micromamba" ]]; then
    echo "Creating ${ENV_NAME} from ${ENV_SPEC}."
    "${ENV_MANAGER}" create --yes --name "${ENV_NAME}" --file "${ENV_SPEC}"
  else
    echo "Creating ${ENV_NAME} from ${ENV_SPEC}."
    "${ENV_MANAGER}" env create --yes --name "${ENV_NAME}" --file "${ENV_SPEC}"
  fi
}

if [[ ! -f "${ENV_SPEC}" ]]; then
  echo "Missing environment specification: ${ENV_SPEC}" >&2
  exit 1
fi

if ENV_MANAGER="$(find_environment_manager)"; then
  :
else
  ENV_MANAGER="$(install_micromamba)"
  export MAMBA_ROOT_PREFIX="${XDG_CACHE_HOME:-${HOME}/.cache}/sr_rf/micromamba"
fi

echo "Repository: ${REPO_ROOT}"
echo "Project: ${PROJECT_DIR}"
echo "Environment manager: ${ENV_MANAGER}"
echo "Environment: ${ENV_NAME}"

if environment_exists; then
  echo "Environment ${ENV_NAME} already exists; keeping the installed base environment."
else
  create_environment
fi

"${ENV_MANAGER}" run --name "${ENV_NAME}" \
  env RIVER_SR_PROJECT_ROOT="${PROJECT_DIR}" \
  Rscript --vanilla "${REPO_ROOT}/environment/bootstrap_r_packages.R" \
  "${PROJECT_DIR}" "${REPO_ROOT}/environment/r-packages.txt"

"${ENV_MANAGER}" run --name "${ENV_NAME}" \
  env RIVER_SR_PROJECT_ROOT="${PROJECT_DIR}" \
  Rscript --vanilla "${REPO_ROOT}/environment/check_environment.R" \
  "${PROJECT_DIR}" "${REPO_ROOT}/environment/r-packages.txt"

echo
echo "sr_rf is ready."
echo "Activate it with: conda activate sr_rf"
