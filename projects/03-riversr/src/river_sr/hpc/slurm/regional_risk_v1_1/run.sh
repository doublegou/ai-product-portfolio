#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
command_name="${1:-}"
run_id="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  bash hpc/slurm/regional_risk_v1_1/run.sh bootstrap
  bash hpc/slurm/regional_risk_v1_1/run.sh check
  bash hpc/slurm/regional_risk_v1_1/run.sh submit [run_id]
  bash hpc/slurm/regional_risk_v1_1/run.sh status [run_id]
  bash hpc/slurm/regional_risk_v1_1/run.sh archive <run_id>

Optional submit environment variables:
  RRISK11_TASK_CPUS       CPUs per task (default: 2)
  RRISK11_TASK_PARALLEL   simultaneous tasks (default: 34)
  RRISK11_CONTROL_CPUS    CPUs for check/aggregate (default: 4)
EOF
}

require_run_id() {
  if [[ -z "$run_id" ]]; then echo "A run_id is required." >&2; usage >&2; exit 2; fi
  if [[ ! "$run_id" =~ ^[A-Za-z0-9._-]+$ ]]; then echo "run_id contains unsupported characters." >&2; exit 2; fi
}

case "$command_name" in
  bootstrap)
    mkdir -p "$repo_root/hpc/transfer"
    export RIVER_SR_ROOT="$repo_root"
    job="$(sbatch --parsable --output="$repo_root/hpc/transfer/rrisk11-bootstrap-%j.out" --error="$repo_root/hpc/transfer/rrisk11-bootstrap-%j.err" "$script_dir/job_bootstrap.sbatch")"
    printf 'Submitted Regional Risk V1.1 environment bootstrap: %s\n' "$job"
    ;;
  check)
    export RIVER_SR_ROOT="$repo_root"
    sbatch --wait --output="$repo_root/hpc/transfer/rrisk11-check-%j.out" --error="$repo_root/hpc/transfer/rrisk11-check-%j.err" "$script_dir/job_check.sbatch"
    ;;
  submit)
    if [[ -z "$run_id" ]]; then run_id="$(date +%Y%m%d_%H%M%S)_regional_risk_v1_1"; fi
    require_run_id
    task_cpus="${RRISK11_TASK_CPUS:-2}"; task_parallel="${RRISK11_TASK_PARALLEL:-34}"; control_cpus="${RRISK11_CONTROL_CPUS:-4}"
    run_dir="$repo_root/training/regional_expert/regional_risk_v1_1/runs/$run_id"
    slurm_log_dir="$run_dir/logs/slurm"; mkdir -p "$slurm_log_dir"
    export RIVER_SR_ROOT="$repo_root" RIVER_SR_RUN_ID="$run_id"
    check_job="$(sbatch --parsable --cpus-per-task="$control_cpus" --output="$slurm_log_dir/check-%j.out" --error="$slurm_log_dir/check-%j.err" "$script_dir/job_check.sbatch")"
    tasks_job="$(sbatch --parsable --dependency="afterok:$check_job" --array="0-33%$task_parallel" --cpus-per-task="$task_cpus" --output="$slurm_log_dir/task-%A_%a.out" --error="$slurm_log_dir/task-%A_%a.err" "$script_dir/job_tasks.sbatch")"
    aggregate_job="$(sbatch --parsable --dependency="afterok:$tasks_job" --cpus-per-task="$control_cpus" --output="$slurm_log_dir/aggregate-%j.out" --error="$slurm_log_dir/aggregate-%j.err" "$script_dir/job_aggregate.sbatch")"
    printf 'stage\tjob_id\ncheck\t%s\ntasks\t%s\naggregate_and_summarize\t%s\n' "$check_job" "$tasks_job" "$aggregate_job" > "$run_dir/slurm_jobs.tsv"
    printf 'Submitted Regional Risk V1.1 run %s\ncheck=%s tasks=%s aggregate=%s\n' "$run_id" "$check_job" "$tasks_job" "$aggregate_job"
    ;;
  status)
    if [[ -n "$run_id" ]]; then
      require_run_id
      jobs_file="$repo_root/training/regional_expert/regional_risk_v1_1/runs/$run_id/slurm_jobs.tsv"
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
    run_path="training/regional_expert/regional_risk_v1_1/runs/$run_id"
    if [[ ! -d "$repo_root/$run_path" ]]; then echo "Missing run directory: $repo_root/$run_path" >&2; exit 1; fi
    mkdir -p "$repo_root/hpc/transfer"; archive_path="$repo_root/hpc/transfer/regional_risk_v1_1_${run_id}.tar.gz"
    cd "$repo_root"
    tar -czf "$archive_path" data/processed/training/himalaya_risk_v1.csv training/regional_expert/regional_risk_v1/folds/branch_map.csv training/regional_expert/regional_risk_v1_1/folds training/regional_expert/regional_risk_v1_1/validation "$run_path"
    sha256sum "$archive_path" > "$archive_path.sha256"
    printf 'Archive: %s\nChecksum: %s.sha256\n' "$archive_path" "$archive_path"
    ;;
  *) usage >&2; exit 2 ;;
esac
