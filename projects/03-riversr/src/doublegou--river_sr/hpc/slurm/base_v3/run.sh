#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
command_name="${1:-}"
run_id="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  bash hpc/slurm/base_v3/run.sh bootstrap
  bash hpc/slurm/base_v3/run.sh submit [run_id]
  bash hpc/slurm/base_v3/run.sh status [run_id]
  bash hpc/slurm/base_v3/run.sh archive <run_id>

Overrides:
  V3_PRIMARY_CPUS=16       V3_PRIMARY_PARALLEL=5
  V3_DEPLOYMENT_CPUS=16    V3_DEPLOYMENT_PARALLEL=2
  V3_STRESS_CPUS=16        V3_STRESS_PARALLEL=10
  V3_CONTROL_CPUS=8
EOF
}

require_run_id() {
  [[ -n "$run_id" ]] || { echo "A run_id is required." >&2; exit 2; }
  [[ "$run_id" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Unsafe run_id." >&2; exit 2; }
}

case "$command_name" in
  bootstrap)
    mkdir -p "$repo_root/hpc/transfer"
    export RIVER_SR_ROOT="$repo_root"
    job="$(sbatch --parsable --output="$repo_root/hpc/transfer/base-v3-bootstrap-%j.out" \
      --error="$repo_root/hpc/transfer/base-v3-bootstrap-%j.err" "$script_dir/job_bootstrap.sbatch")"
    echo "Submitted Base V3 bootstrap: $job"
    ;;
  submit)
    if [[ -z "$run_id" ]]; then run_id="base_v3_full_$(date +%Y%m%d_%H%M%S)"; fi
    require_run_id
    primary_cpus="${V3_PRIMARY_CPUS:-16}"
    primary_parallel="${V3_PRIMARY_PARALLEL:-5}"
    deployment_cpus="${V3_DEPLOYMENT_CPUS:-16}"
    deployment_parallel="${V3_DEPLOYMENT_PARALLEL:-2}"
    stress_cpus="${V3_STRESS_CPUS:-16}"
    stress_parallel="${V3_STRESS_PARALLEL:-10}"
    control_cpus="${V3_CONTROL_CPUS:-8}"
    run_dir="$repo_root/training/base/v3/runs/$run_id"
    log_dir="$run_dir/logs/slurm"
    mkdir -p "$log_dir"
    export RIVER_SR_ROOT="$repo_root" RIVER_SR_RUN_ID="$run_id"

    check_job="$(sbatch --parsable --cpus-per-task="$control_cpus" --output="$log_dir/check-%j.out" --error="$log_dir/check-%j.err" "$script_dir/job_check.sbatch")"
    rf_job="$(sbatch --parsable --dependency="afterok:$check_job" --array="1-15%$primary_parallel" --cpus-per-task="$primary_cpus" \
      --output="$log_dir/primary-rf-%A_%a.out" --error="$log_dir/primary-rf-%A_%a.err" "$script_dir/job_primary_rf.sbatch")"
    xgb_job="$(sbatch --parsable --dependency="afterok:$check_job" --array="1-15%$primary_parallel" --cpus-per-task="$primary_cpus" \
      --output="$log_dir/primary-xgb-%A_%a.out" --error="$log_dir/primary-xgb-%A_%a.err" "$script_dir/job_primary_xgb.sbatch")"
    aggregate_job="$(sbatch --parsable --dependency="afterok:$rf_job:$xgb_job" --cpus-per-task="$control_cpus" \
      --output="$log_dir/aggregate-%j.out" --error="$log_dir/aggregate-%j.err" "$script_dir/job_aggregate.sbatch")"
    deployment_job="$(sbatch --parsable --dependency="afterok:$aggregate_job" --array="1-2%$deployment_parallel" --cpus-per-task="$deployment_cpus" \
      --output="$log_dir/deployment-%A_%a.out" --error="$log_dir/deployment-%A_%a.err" "$script_dir/job_deployment.sbatch")"
    stress_rf_job="$(sbatch --parsable --dependency="afterok:$deployment_job" --array="1-20%$stress_parallel" --cpus-per-task="$stress_cpus" \
      --output="$log_dir/stress-rf-%A_%a.out" --error="$log_dir/stress-rf-%A_%a.err" "$script_dir/job_stress_rf.sbatch")"
    stress_xgb_job="$(sbatch --parsable --dependency="afterok:$deployment_job" --array="1-20%$stress_parallel" --cpus-per-task="$stress_cpus" \
      --output="$log_dir/stress-xgb-%A_%a.out" --error="$log_dir/stress-xgb-%A_%a.err" "$script_dir/job_stress_xgb.sbatch")"
    finalize_job="$(sbatch --parsable --dependency="afterok:$stress_rf_job:$stress_xgb_job" --cpus-per-task="$control_cpus" \
      --output="$log_dir/finalize-%j.out" --error="$log_dir/finalize-%j.err" "$script_dir/job_finalize.sbatch")"
    result_check_job="$(sbatch --parsable --dependency="afterok:$finalize_job" --cpus-per-task="$control_cpus" \
      --output="$log_dir/result-check-%j.out" --error="$log_dir/result-check-%j.err" "$script_dir/job_result_check.sbatch")"

    printf 'stage\tjob_id\ncheck\t%s\nprimary_rf\t%s\nprimary_xgb\t%s\naggregate\t%s\ndeployment\t%s\nstress_rf\t%s\nstress_xgb\t%s\nfinalize\t%s\nresult_check\t%s\n' \
      "$check_job" "$rf_job" "$xgb_job" "$aggregate_job" "$deployment_job" "$stress_rf_job" "$stress_xgb_job" "$finalize_job" "$result_check_job" \
      > "$run_dir/slurm_jobs.tsv"
    echo "Submitted Base V3 run $run_id"
    ;;
  status)
    if [[ -n "$run_id" ]]; then
      require_run_id
      jobs_file="$repo_root/training/base/v3/runs/$run_id/slurm_jobs.tsv"
      [[ -f "$jobs_file" ]] || { echo "Missing $jobs_file" >&2; exit 1; }
      job_ids="$(awk 'NR>1 {print $2}' "$jobs_file" | paste -sd, -)"
      squeue --jobs="$job_ids" --format='%.18i %.28j %.9T %.10M %.6D %R' || true
      sacct --jobs="$job_ids" --format=JobID,JobName%28,State,Elapsed,AllocCPUS,MaxRSS,ExitCode || true
    else
      squeue --user="$USER" --format='%.18i %.28j %.9T %.10M %.6D %R'
    fi
    ;;
  archive)
    require_run_id
    run_path="training/base/v3/runs/$run_id"
    [[ -d "$repo_root/$run_path" ]] || { echo "Missing $run_path" >&2; exit 1; }
    mkdir -p "$repo_root/hpc/transfer"
    archive="$repo_root/hpc/transfer/base_v3_${run_id}.tar.gz"
    cd "$repo_root"
    tar -czf "$archive" training/base/v3/config training/base/v3/folds "$run_path"
    sha256sum "$archive" > "$archive.sha256"
    echo "Archive: $archive"
    echo "Checksum: $archive.sha256"
    ;;
  *) usage >&2; exit 2 ;;
esac
