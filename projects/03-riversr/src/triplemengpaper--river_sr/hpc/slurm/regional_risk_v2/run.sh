#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
command_name="${1:-}"; run_id="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  bash hpc/slurm/regional_risk_v2/run.sh bootstrap
  bash hpc/slurm/regional_risk_v2/run.sh check
  bash hpc/slurm/regional_risk_v2/run.sh submit [run_id]
  bash hpc/slurm/regional_risk_v2/run.sh status [run_id]
  bash hpc/slurm/regional_risk_v2/run.sh archive <run_id>

Optional: RRISK2_TASK_CPUS=2 RRISK2_TASK_PARALLEL=34 RRISK2_CONTROL_CPUS=4
EOF
}

require_run_id() {
  [[ -n "$run_id" ]] || { echo "A run_id is required." >&2; exit 2; }
  [[ "$run_id" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Unsupported run_id." >&2; exit 2; }
}

case "$command_name" in
  bootstrap)
    mkdir -p "$repo_root/hpc/transfer"; export RIVER_SR_ROOT="$repo_root"
    job="$(sbatch --parsable --output="$repo_root/hpc/transfer/rrisk2-bootstrap-%j.out" --error="$repo_root/hpc/transfer/rrisk2-bootstrap-%j.err" "$script_dir/job_bootstrap.sbatch")"
    printf 'Submitted V2 environment bootstrap: %s\n' "$job" ;;
  check)
    mkdir -p "$repo_root/hpc/transfer"; export RIVER_SR_ROOT="$repo_root"
    sbatch --wait --output="$repo_root/hpc/transfer/rrisk2-check-%j.out" --error="$repo_root/hpc/transfer/rrisk2-check-%j.err" "$script_dir/job_check.sbatch" ;;
  submit)
    [[ -n "$run_id" ]] || run_id="$(date +%Y%m%d_%H%M%S)_regional_risk_v2"; require_run_id
    task_cpus="${RRISK2_TASK_CPUS:-2}"; task_parallel="${RRISK2_TASK_PARALLEL:-34}"; control_cpus="${RRISK2_CONTROL_CPUS:-4}"
    run_dir="$repo_root/training/regional_expert/regional_risk_v2/runs/$run_id"; slurm_log_dir="$run_dir/logs/slurm"; mkdir -p "$slurm_log_dir"
    export RIVER_SR_ROOT="$repo_root" RIVER_SR_RUN_ID="$run_id"
    check_job="$(sbatch --parsable --cpus-per-task="$control_cpus" --output="$slurm_log_dir/check-%j.out" --error="$slurm_log_dir/check-%j.err" "$script_dir/job_check.sbatch")"
    tasks_job="$(sbatch --parsable --dependency="afterok:$check_job" --array="0-67%$task_parallel" --cpus-per-task="$task_cpus" --output="$slurm_log_dir/task-%A_%a.out" --error="$slurm_log_dir/task-%A_%a.err" "$script_dir/job_tasks.sbatch")"
    aggregate_job="$(sbatch --parsable --dependency="afterok:$tasks_job" --cpus-per-task="$control_cpus" --output="$slurm_log_dir/aggregate-%j.out" --error="$slurm_log_dir/aggregate-%j.err" "$script_dir/job_aggregate.sbatch")"
    printf 'stage\tjob_id\ncheck\t%s\ntasks\t%s\naggregate_and_summarize\t%s\n' "$check_job" "$tasks_job" "$aggregate_job" > "$run_dir/slurm_jobs.tsv"
    printf 'Submitted V2 run %s\ncheck=%s tasks=%s aggregate=%s\n' "$run_id" "$check_job" "$tasks_job" "$aggregate_job" ;;
  status)
    if [[ -n "$run_id" ]]; then require_run_id; jobs="$repo_root/training/regional_expert/regional_risk_v2/runs/$run_id/slurm_jobs.tsv"; [[ -f "$jobs" ]] || { echo "Missing $jobs" >&2; exit 1; }
      ids="$(awk 'NR > 1 {print $2}' "$jobs" | paste -sd, -)"; squeue --jobs="$ids" --format='%.18i %.28j %.9T %.10M %.6D %R' || true; sacct --jobs="$ids" --format=JobID,JobName%28,State,Elapsed,AllocCPUS,MaxRSS,ExitCode || true
    else squeue --user="$USER" --format='%.18i %.28j %.9T %.10M %.6D %R'; fi ;;
  archive)
    require_run_id; run_path="training/regional_expert/regional_risk_v2/runs/$run_id"; [[ -d "$repo_root/$run_path" ]] || { echo "Missing run." >&2; exit 1; }
    mkdir -p "$repo_root/hpc/transfer"; archive="$repo_root/hpc/transfer/regional_risk_v2_${run_id}.tar.gz"; cd "$repo_root"
    tar -czf "$archive" data/processed/training/himalaya_risk_v2.csv training/regional_expert/regional_risk_v2/folds training/regional_expert/regional_risk_v2/validation "$run_path"
    sha256sum "$archive" > "$archive.sha256"; printf 'Archive: %s\nChecksum: %s.sha256\n' "$archive" "$archive" ;;
  *) usage >&2; exit 2 ;;
esac
