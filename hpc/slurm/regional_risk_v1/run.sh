#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
command_name="${1:-}"
run_id="${2:-}"

usage() {
  cat <<'EOF'
Usage:
  bash hpc/slurm/regional_risk_v1/run.sh bootstrap
  bash hpc/slurm/regional_risk_v1/run.sh check
  bash hpc/slurm/regional_risk_v1/run.sh submit [run_id]
  bash hpc/slurm/regional_risk_v1/run.sh status [run_id]
  bash hpc/slurm/regional_risk_v1/run.sh archive <run_id>

Optional submit environment variables:
  REGIONAL_GAM_CPUS          CPUs per GAM task (default: 2)
  REGIONAL_GAM_PARALLEL      Simultaneous GAM tasks (default: 51)
  REGIONAL_ELASTIC_CPUS      CPUs per Elastic task (default: 2)
  REGIONAL_ELASTIC_PARALLEL  Simultaneous Elastic tasks (default: 34)
  REGIONAL_CONTROL_CPUS      CPUs for check/aggregate (default: 4)
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
    job="$(sbatch --parsable --output="$repo_root/hpc/transfer/regional-risk-bootstrap-%j.out" --error="$repo_root/hpc/transfer/regional-risk-bootstrap-%j.err" "$script_dir/job_bootstrap.sbatch")"
    printf 'Submitted Regional Risk V1 environment bootstrap: %s\n' "$job"
    ;;
  check)
    export RIVER_SR_ROOT="$repo_root"
    sbatch --wait --output="$repo_root/hpc/transfer/regional-risk-check-%j.out" --error="$repo_root/hpc/transfer/regional-risk-check-%j.err" "$script_dir/job_check.sbatch"
    ;;
  submit)
    if [[ -z "$run_id" ]]; then run_id="$(date +%Y%m%d_%H%M%S)_regional_risk_v1"; fi
    require_run_id
    gam_cpus="${REGIONAL_GAM_CPUS:-2}"; gam_parallel="${REGIONAL_GAM_PARALLEL:-51}"
    elastic_cpus="${REGIONAL_ELASTIC_CPUS:-2}"; elastic_parallel="${REGIONAL_ELASTIC_PARALLEL:-34}"
    control_cpus="${REGIONAL_CONTROL_CPUS:-4}"
    run_dir="$repo_root/training/regional_expert/risk_v1/runs/$run_id"
    slurm_log_dir="$run_dir/logs/slurm"; mkdir -p "$slurm_log_dir"
    export RIVER_SR_ROOT="$repo_root" RIVER_SR_RUN_ID="$run_id"
    check_job="$(sbatch --parsable --cpus-per-task="$control_cpus" --output="$slurm_log_dir/check-%j.out" --error="$slurm_log_dir/check-%j.err" "$script_dir/job_check.sbatch")"
    gam_job="$(sbatch --parsable --dependency="afterok:$check_job" --array="0-50%$gam_parallel" --cpus-per-task="$gam_cpus" --output="$slurm_log_dir/gam-%A_%a.out" --error="$slurm_log_dir/gam-%A_%a.err" "$script_dir/job_gam.sbatch")"
    elastic_job="$(sbatch --parsable --dependency="afterok:$check_job" --array="0-33%$elastic_parallel" --cpus-per-task="$elastic_cpus" --output="$slurm_log_dir/elastic-%A_%a.out" --error="$slurm_log_dir/elastic-%A_%a.err" "$script_dir/job_elastic.sbatch")"
    aggregate_job="$(sbatch --parsable --dependency="afterok:$gam_job:$elastic_job" --cpus-per-task="$control_cpus" --output="$slurm_log_dir/aggregate-%j.out" --error="$slurm_log_dir/aggregate-%j.err" "$script_dir/job_aggregate.sbatch")"
    printf 'stage\tjob_id\ncheck\t%s\ngam_array\t%s\nelastic_array\t%s\naggregate_and_summarize\t%s\n' "$check_job" "$gam_job" "$elastic_job" "$aggregate_job" > "$run_dir/slurm_jobs.tsv"
    printf 'Submitted Regional Risk V1 run %s\ncheck=%s gam=%s elastic=%s aggregate=%s\n' "$run_id" "$check_job" "$gam_job" "$elastic_job" "$aggregate_job"
    ;;
  status)
    if [[ -n "$run_id" ]]; then
      require_run_id
      jobs_file="$repo_root/training/regional_expert/risk_v1/runs/$run_id/slurm_jobs.tsv"
      if [[ ! -f "$jobs_file" ]]; then echo "Missing Slurm job manifest: $jobs_file" >&2; exit 1; fi
      job_ids="$(awk 'NR > 1 {print $2}' "$jobs_file" | paste -sd, -)"
      squeue --jobs="$job_ids" --format='%.18i %.28j %.9T %.10M %.6D %R' || true
      sacct --jobs="$job_ids" --format=JobID,JobName%28,State,Elapsed,AllocCPUS,MaxRSS,ExitCode || true
    else squeue --user="$USER" --format='%.18i %.28j %.9T %.10M %.6D %R'; fi
    ;;
  archive)
    require_run_id
    run_path="training/regional_expert/risk_v1/runs/$run_id"
    if [[ ! -d "$repo_root/$run_path" ]]; then echo "Missing run directory: $repo_root/$run_path" >&2; exit 1; fi
    mkdir -p "$repo_root/hpc/transfer"; archive_path="$repo_root/hpc/transfer/regional_risk_v1_${run_id}.tar.gz"
    cd "$repo_root"
    tar -czf "$archive_path" data/processed/training/himalaya_risk_v1.csv training/regional_expert/risk_v1/folds training/regional_expert/risk_v1/validation "$run_path"
    sha256sum "$archive_path" > "$archive_path.sha256"
    printf 'Archive: %s\nChecksum: %s.sha256\n' "$archive_path" "$archive_path"
    ;;
  *) usage >&2; exit 2 ;;
esac
