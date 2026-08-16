#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
command_name="${1:-}"
run_id="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  bash hpc/slurm/base_v0/run.sh bootstrap
  bash hpc/slurm/base_v0/run.sh submit [run_id]
  bash hpc/slurm/base_v0/run.sh status [run_id]
  bash hpc/slurm/base_v0/run.sh archive <run_id>

Optional environment variables for submit:
  V0_CPUS_PER_TASK   CPUs per validation/final task (default: 32)
  V0_MAX_PARALLEL    Maximum simultaneous validation tasks (default: 20)
EOF
}

require_run_id() {
  if [[ -z "$run_id" ]]; then
    echo "A run_id is required." >&2
    usage >&2
    exit 2
  fi
  if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "run_id may only contain letters, numbers, dot, underscore and hyphen." >&2
    exit 2
  fi
}

case "$command_name" in
  bootstrap)
    bootstrap_log_dir="$repo_root/hpc/transfer"
    mkdir -p "$bootstrap_log_dir"
    export RIVER_SR_ROOT="$repo_root"
    bootstrap_job="$(sbatch --parsable \
      --output="$bootstrap_log_dir/bootstrap-%j.out" \
      --error="$bootstrap_log_dir/bootstrap-%j.err" \
      "$script_dir/job_bootstrap.sbatch")"
    printf 'Submitted Base V0 environment bootstrap: %s\n' "$bootstrap_job"
    ;;

  submit)
    if [[ -z "$run_id" ]]; then
      run_id="$(date +%Y%m%d_%H%M%S)_full"
    fi
    require_run_id
    cpus_per_task="${V0_CPUS_PER_TASK:-32}"
    max_parallel="${V0_MAX_PARALLEL:-20}"
    run_dir="$repo_root/training/base/v0/runs/$run_id"
    slurm_log_dir="$run_dir/logs/slurm"
    mkdir -p "$slurm_log_dir"

    export RIVER_SR_ROOT="$repo_root"
    export RIVER_SR_RUN_ID="$run_id"

    prepare_job="$(sbatch --parsable \
      --output="$slurm_log_dir/prepare-%j.out" \
      --error="$slurm_log_dir/prepare-%j.err" \
      "$script_dir/job_prepare.sbatch")"
    validation_job="$(sbatch --parsable \
      --dependency="afterok:$prepare_job" \
      --array="0-19%$max_parallel" \
      --cpus-per-task="$cpus_per_task" \
      --output="$slurm_log_dir/validation-%A_%a.out" \
      --error="$slurm_log_dir/validation-%A_%a.err" \
      "$script_dir/job_validation.sbatch")"
    finalize_job="$(sbatch --parsable \
      --dependency="afterok:$validation_job" \
      --cpus-per-task="$cpus_per_task" \
      --output="$slurm_log_dir/finalize-%j.out" \
      --error="$slurm_log_dir/finalize-%j.err" \
      "$script_dir/job_finalize.sbatch")"

    printf 'stage\tjob_id\nprepare\t%s\nvalidation_array\t%s\nfinalize\t%s\n' \
      "$prepare_job" "$validation_job" "$finalize_job" \
      > "$run_dir/slurm_jobs.tsv"
    printf 'Submitted Base V0 run %s\n' "$run_id"
    printf 'prepare=%s validation=%s finalize=%s\n' \
      "$prepare_job" "$validation_job" "$finalize_job"
    ;;

  status)
    if [[ -n "$run_id" ]]; then
      require_run_id
      jobs_file="$repo_root/training/base/v0/runs/$run_id/slurm_jobs.tsv"
      if [[ ! -f "$jobs_file" ]]; then
        echo "Missing Slurm job manifest: $jobs_file" >&2
        exit 1
      fi
      job_ids="$(awk 'NR > 1 {print $2}' "$jobs_file" | paste -sd, -)"
      squeue --jobs="$job_ids" --format='%.18i %.28j %.9T %.10M %.6D %R' || true
      sacct --jobs="$job_ids" --format=JobID,JobName%28,State,Elapsed,AllocCPUS,MaxRSS,ExitCode || true
    else
      squeue --user="$USER" --format='%.18i %.28j %.9T %.10M %.6D %R'
    fi
    ;;

  archive)
    require_run_id
    run_path="training/base/v0/runs/$run_id"
    if [[ ! -d "$repo_root/$run_path" ]]; then
      echo "Missing run directory: $repo_root/$run_path" >&2
      exit 1
    fi
    transfer_dir="$repo_root/hpc/transfer"
    mkdir -p "$transfer_dir"
    archive_path="$transfer_dir/base_v0_${run_id}.tar.gz"
    checksum_path="$archive_path.sha256"
    cd "$repo_root"
    tar -czf "$archive_path" \
      training/base/v0/folds \
      training/base/v0/validation \
      "$run_path"
    sha256sum "$archive_path" > "$checksum_path"
    printf 'Archive: %s\nChecksum: %s\n' "$archive_path" "$checksum_path"
    ;;

  *)
    usage >&2
    exit 2
    ;;
esac
