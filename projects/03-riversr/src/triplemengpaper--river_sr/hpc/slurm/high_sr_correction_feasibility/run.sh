#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
command_name="${1:-}"
run_id="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  bash hpc/slurm/high_sr_correction_feasibility/run.sh bootstrap
  bash hpc/slurm/high_sr_correction_feasibility/run.sh check
  bash hpc/slurm/high_sr_correction_feasibility/run.sh submit [run_id]
  bash hpc/slurm/high_sr_correction_feasibility/run.sh status [run_id]
  bash hpc/slurm/high_sr_correction_feasibility/run.sh archive <run_id>

Optional environment variables for submit:
  CORR_BASE_CPUS       CPUs per strict-nested Base task (default: 32)
  CORR_BASE_PARALLEL   Maximum simultaneous Base tasks (default: 15)
  CORR_ELASTIC_CPUS    CPUs per Elastic-net task (default: 4)
  CORR_ELASTIC_PARALLEL Maximum simultaneous Elastic-net tasks (default: 15)
  CORR_RF_CPUS         CPUs per residual-RF task (default: 32)
  CORR_RF_PARALLEL     Maximum simultaneous residual-RF tasks (default: 15)
  CORR_CONTROL_CPUS    CPUs for check/aggregate/decision (default: 4)
EOF
}

require_run_id() {
  if [[ -z "$run_id" ]]; then echo "A run_id is required." >&2; usage >&2; exit 2; fi
  if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ]]; then echo "run_id may only contain letters, numbers, dot, underscore and hyphen." >&2; exit 2; fi
}

case "$command_name" in
  bootstrap)
    mkdir -p "$repo_root/hpc/transfer"
    export RIVER_SR_ROOT="$repo_root"
    job="$(sbatch --parsable --output="$repo_root/hpc/transfer/corr-bootstrap-%j.out" --error="$repo_root/hpc/transfer/corr-bootstrap-%j.err" "$script_dir/job_bootstrap.sbatch")"
    printf 'Submitted correction environment bootstrap: %s\n' "$job"
    ;;
  check)
    export RIVER_SR_ROOT="$repo_root"
    sbatch --wait --output="$repo_root/hpc/transfer/corr-check-%j.out" --error="$repo_root/hpc/transfer/corr-check-%j.err" "$script_dir/job_check.sbatch"
    ;;
  submit)
    if [[ -z "$run_id" ]]; then run_id="$(date +%Y%m%d_%H%M%S)_high_sr_correction"; fi
    require_run_id
    base_cpus="${CORR_BASE_CPUS:-32}"; base_parallel="${CORR_BASE_PARALLEL:-15}"
    elastic_cpus="${CORR_ELASTIC_CPUS:-4}"; elastic_parallel="${CORR_ELASTIC_PARALLEL:-15}"
    rf_cpus="${CORR_RF_CPUS:-32}"; rf_parallel="${CORR_RF_PARALLEL:-15}"
    control_cpus="${CORR_CONTROL_CPUS:-4}"
    run_dir="$repo_root/training/global_correction/high_sr_correction_feasibility/runs/$run_id"
    slurm_log_dir="$run_dir/logs/slurm"
    mkdir -p "$slurm_log_dir"
    export RIVER_SR_ROOT="$repo_root" RIVER_SR_RUN_ID="$run_id"
    check_job="$(sbatch --parsable --cpus-per-task="$control_cpus" --output="$slurm_log_dir/check-%j.out" --error="$slurm_log_dir/check-%j.err" "$script_dir/job_check.sbatch")"
    base_job="$(sbatch --parsable --dependency="afterok:$check_job" --array="0-14%$base_parallel" --cpus-per-task="$base_cpus" --output="$slurm_log_dir/base-%A_%a.out" --error="$slurm_log_dir/base-%A_%a.err" "$script_dir/job_base.sbatch")"
    elastic_job="$(sbatch --parsable --dependency="afterok:$base_job" --array="0-14%$elastic_parallel" --cpus-per-task="$elastic_cpus" --output="$slurm_log_dir/elastic-%A_%a.out" --error="$slurm_log_dir/elastic-%A_%a.err" "$script_dir/job_elastic.sbatch")"
    rf_job="$(sbatch --parsable --dependency="afterok:$base_job" --array="0-14%$rf_parallel" --cpus-per-task="$rf_cpus" --output="$slurm_log_dir/rf-%A_%a.out" --error="$slurm_log_dir/rf-%A_%a.err" "$script_dir/job_rf.sbatch")"
    aggregate_job="$(sbatch --parsable --dependency="afterok:$elastic_job:$rf_job" --cpus-per-task="$control_cpus" --output="$slurm_log_dir/aggregate-%j.out" --error="$slurm_log_dir/aggregate-%j.err" "$script_dir/job_aggregate.sbatch")"
    decide_job="$(sbatch --parsable --dependency="afterok:$aggregate_job" --cpus-per-task="$control_cpus" --output="$slurm_log_dir/decide-%j.out" --error="$slurm_log_dir/decide-%j.err" "$script_dir/job_decide.sbatch")"
    printf 'stage\tjob_id\ncheck\t%s\nbase_array\t%s\nelastic_array\t%s\nrf_array\t%s\naggregate\t%s\ndecide\t%s\n' "$check_job" "$base_job" "$elastic_job" "$rf_job" "$aggregate_job" "$decide_job" > "$run_dir/slurm_jobs.tsv"
    printf 'Submitted High-Sr Correction Feasibility run %s\n' "$run_id"
    printf 'check=%s base=%s elastic=%s rf=%s aggregate=%s decide=%s\n' "$check_job" "$base_job" "$elastic_job" "$rf_job" "$aggregate_job" "$decide_job"
    ;;
  status)
    if [[ -n "$run_id" ]]; then
      require_run_id
      jobs_file="$repo_root/training/global_correction/high_sr_correction_feasibility/runs/$run_id/slurm_jobs.tsv"
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
    run_path="training/global_correction/high_sr_correction_feasibility/runs/$run_id"
    if [[ ! -d "$repo_root/$run_path" ]]; then echo "Missing run directory: $repo_root/$run_path" >&2; exit 1; fi
    mkdir -p "$repo_root/hpc/transfer"
    archive_path="$repo_root/hpc/transfer/high_sr_correction_feasibility_${run_id}.tar.gz"
    cd "$repo_root"
    tar -czf "$archive_path" training/global_correction/high_sr_correction_feasibility/folds training/global_correction/high_sr_correction_feasibility/validation "$run_path"
    sha256sum "$archive_path" > "$archive_path.sha256"
    printf 'Archive: %s\nChecksum: %s.sha256\n' "$archive_path" "$archive_path"
    ;;
  *) usage >&2; exit 2 ;;
esac
