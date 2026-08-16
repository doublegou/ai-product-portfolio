#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
command_name="${1:-}"
run_id="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  bash hpc/slurm/base_v1/run.sh bootstrap
  bash hpc/slurm/base_v1/run.sh submit [run_id]
  bash hpc/slurm/base_v1/run.sh status [run_id]
  bash hpc/slurm/base_v1/run.sh archive <run_id>

Optional environment variables for submit:
  V1_PRIMARY_CPUS     CPUs per Primary task (default: 32)
  V1_PRIMARY_PARALLEL Maximum simultaneous Primary tasks (default: 15)
  V1_STRESS_CPUS      CPUs per stress task (default: 16)
  V1_STRESS_PARALLEL  Maximum simultaneous stress tasks (default: 20)
  V1_CONTROL_CPUS     CPUs for deployment/final model (default: 32)
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
    job="$(sbatch --parsable \
      --output="$bootstrap_log_dir/base-v1-bootstrap-%j.out" \
      --error="$bootstrap_log_dir/base-v1-bootstrap-%j.err" \
      "$script_dir/job_bootstrap.sbatch")"
    printf 'Submitted Base V1 environment bootstrap: %s\n' "$job"
    ;;

  submit)
    if [[ -z "$run_id" ]]; then run_id="$(date +%Y%m%d_%H%M%S)_full"; fi
    require_run_id
    primary_cpus="${V1_PRIMARY_CPUS:-32}"
    primary_parallel="${V1_PRIMARY_PARALLEL:-15}"
    stress_cpus="${V1_STRESS_CPUS:-16}"
    stress_parallel="${V1_STRESS_PARALLEL:-20}"
    control_cpus="${V1_CONTROL_CPUS:-32}"
    run_dir="$repo_root/training/base/v1/runs/$run_id"
    slurm_log_dir="$run_dir/logs/slurm"
    mkdir -p "$slurm_log_dir"
    export RIVER_SR_ROOT="$repo_root"
    export RIVER_SR_RUN_ID="$run_id"

    check_job="$(sbatch --parsable \
      --output="$slurm_log_dir/check-%j.out" \
      --error="$slurm_log_dir/check-%j.err" \
      "$script_dir/job_check.sbatch")"
    primary_job="$(sbatch --parsable \
      --dependency="afterok:$check_job" \
      --array="0-14%$primary_parallel" \
      --cpus-per-task="$primary_cpus" \
      --output="$slurm_log_dir/primary-%A_%a.out" \
      --error="$slurm_log_dir/primary-%A_%a.err" \
      "$script_dir/job_primary.sbatch")"
    deployment_job="$(sbatch --parsable \
      --dependency="afterok:$primary_job" \
      --cpus-per-task="$control_cpus" \
      --output="$slurm_log_dir/deployment-%j.out" \
      --error="$slurm_log_dir/deployment-%j.err" \
      "$script_dir/job_deployment.sbatch")"
    stress_job="$(sbatch --parsable \
      --dependency="afterok:$deployment_job" \
      --array="0-19%$stress_parallel" \
      --cpus-per-task="$stress_cpus" \
      --output="$slurm_log_dir/stress-%A_%a.out" \
      --error="$slurm_log_dir/stress-%A_%a.err" \
      "$script_dir/job_stress.sbatch")"
    finalize_job="$(sbatch --parsable \
      --dependency="afterok:$stress_job" \
      --cpus-per-task="$control_cpus" \
      --output="$slurm_log_dir/finalize-%j.out" \
      --error="$slurm_log_dir/finalize-%j.err" \
      "$script_dir/job_finalize.sbatch")"

    printf 'stage\tjob_id\ncheck\t%s\nprimary_array\t%s\ndeployment\t%s\nstress_array\t%s\nfinalize\t%s\n' \
      "$check_job" "$primary_job" "$deployment_job" "$stress_job" "$finalize_job" \
      > "$run_dir/slurm_jobs.tsv"
    printf 'Submitted Base V1 run %s\n' "$run_id"
    printf 'check=%s primary=%s deployment=%s stress=%s finalize=%s\n' \
      "$check_job" "$primary_job" "$deployment_job" "$stress_job" "$finalize_job"
    ;;

  status)
    if [[ -n "$run_id" ]]; then
      require_run_id
      jobs_file="$repo_root/training/base/v1/runs/$run_id/slurm_jobs.tsv"
      if [[ ! -f "$jobs_file" ]]; then echo "Missing Slurm job manifest: $jobs_file" >&2; exit 1; fi
      job_ids="$(awk 'NR > 1 {print $2}' "$jobs_file" | paste -sd, -)"
      squeue --jobs="$job_ids" --format='%.18i %.28j %.9T %.10M %.6D %R' || true
      sacct --jobs="$job_ids" --format=JobID,JobName%28,State,Elapsed,AllocCPUS,MaxRSS,ExitCode || true
    else
      squeue --user="$USER" --format='%.18i %.28j %.9T %.10M %.6D %R'
    fi
    ;;

  archive)
    require_run_id
    run_path="training/base/v1/runs/$run_id"
    if [[ ! -d "$repo_root/$run_path" ]]; then echo "Missing run directory: $repo_root/$run_path" >&2; exit 1; fi
    transfer_dir="$repo_root/hpc/transfer"
    mkdir -p "$transfer_dir"
    archive_path="$transfer_dir/base_v1_${run_id}.tar.gz"
    checksum_path="$archive_path.sha256"
    cd "$repo_root"
    tar -czf "$archive_path" training/base/v1/folds training/base/v1/validation "$run_path"
    sha256sum "$archive_path" > "$checksum_path"
    printf 'Archive: %s\nChecksum: %s\n' "$archive_path" "$checksum_path"
    ;;

  *) usage >&2; exit 2 ;;
esac
