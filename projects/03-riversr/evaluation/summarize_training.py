"""Reconstruct application timing from retained logs, without running models.

Time fields are application timestamps, not Slurm accounting. Match the latest
complete interval to task_info; reject logs inconsistent with that task version.
"""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import re
import statistics

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'src/river_sr'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(family):
    tasks = []
    for log in sorted((SOURCE / 'training/regional_expert' / family / 'validation').glob('*/*/run.log')):
        info_path = log.with_name('task_info.json')
        info = json.loads(info_path.read_text())
        pairs, started = [], None
        for stamp, message in re.findall(r'^\[([^]]+)\] (.*)$', log.read_text(), re.M):
            if 'Starting task' in message:
                match = re.search(r'Starting task\s+(\d+)\s*:\s*([^,]+),', message)
                if not match or int(match[1]) != info['task_id'] or match[2].strip() != info['model_id']:
                    raise ValueError(f'Task identity mismatch: {log}')
                started = datetime.fromisoformat(stamp)
            if re.search(r'Task\s+\d+\s+complete', message) and started is not None:
                pairs.append((started, datetime.fromisoformat(stamp)))
                started = None
        if not pairs or started is not None or info['status'] != 'complete':
            raise ValueError(f'Incomplete task: {log}')
        start, end = pairs[-1]
        meta_end = datetime.fromisoformat(info['completed_at']).replace(tzinfo=None)
        # task_info is saved before the completion log; timestamps have 1s precision.
        delta = (end - meta_end).total_seconds()
        if not 0 <= delta <= 1 or end < start:
            raise ValueError(f'Latest log does not match task metadata: {log}')
        tasks.append({
            'model': info['model_id'], 'task_id': info['task_id'],
            'slurm_job_id': info['runtime']['slurm_job_id'],
            'start': start.isoformat(), 'end': end.isoformat(),
            'application_seconds': int((end - start).total_seconds()),
            'older_intervals_excluded': len(pairs) - 1,
            'log': str(log.relative_to(ROOT)), 'log_sha256': digest(log),
            'task_info_sha256': digest(info_path),
        })
    expected = {'regional_risk_v1': 85, 'regional_risk_v1_1': 34}[family]
    if len(tasks) != expected or len({x['task_id'] for x in tasks}) != expected:
        raise ValueError(f'Incomplete or duplicate population: {family}')
    groups = {}
    for model in sorted({x['model'] for x in tasks}):
        values = [x['application_seconds'] for x in tasks if x['model'] == model]
        groups[model] = {'tasks': len(values), 'min_seconds': min(values),
                         'median_seconds': statistics.median(values), 'max_seconds': max(values),
                         'summed_task_seconds': sum(values)}
    first, last = min(x['start'] for x in tasks), max(x['end'] for x in tasks)
    return {'tasks': len(tasks), 'first_start': first, 'last_end': last,
            'application_window_seconds': int((datetime.fromisoformat(last)-datetime.fromisoformat(first)).total_seconds()),
            'summed_task_seconds': sum(x['application_seconds'] for x in tasks),
            'groups': groups, 'records': tasks}


def protocol_budget():
    path = SOURCE / 'training/base/v3/config/base_v3.yml'
    # These scalar keys are shared by both model blocks; require consistent values.
    text = path.read_text()
    def scalar(key):
        values = {int(x) for x in re.findall(r'^  '+key+r': (\d+)\s*$', text, re.M)}
        if len(values) != 1:
            raise ValueError(f'Non-unique protocol scalar: {key}')
        return values.pop()
    outer = scalar('outer_repeats') * scalar('outer_folds')
    weights = re.findall(r'^  W\d+:', text, re.M)
    tuning = (scalar('coarse_structures') + scalar('refinement_structures')) * len(weights) * scalar('inner_folds')
    return {'basis': 'configuration-derived planned fit calls, not execution accounting',
            'config': str(path.relative_to(ROOT)), 'config_sha256': digest(path),
            'models': 2, 'outer_tasks_per_model': outer, 'tuning_fits_per_outer_task': tuning,
            'outer_refits_per_task': 1, 'primary_fit_calls': 2 * outer * (tuning + 1),
            'excludes': ['deployment tuning', 'stress', 'full-data fitting', 'smoke', 'failed or resumed attempts']}


if __name__ == '__main__':
    report = {'scope': 'repository-retained Regional Risk V1/V1.1 application logs and Base V3 protocol',
              'timestamp_precision_seconds': 1,
              'not_accounting_for': ['queue wait', 'R/package startup before application log',
                                     'other workflow stages', 'allocated CPU time', 'billing'],
              'base_v3_total_wall_seconds': None, 'base_v3_allocated_cpu_hours': None,
              'actual_currency_cost': None,
              'protocol_budget': protocol_budget(),
              'runs': {x: summarize(x) for x in ['regional_risk_v1', 'regional_risk_v1_1']}}
    output = ROOT / 'evaluation/training-evidence.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'primary_planned_fit_calls': report['protocol_budget']['primary_fit_calls'],
                      'application_log_tasks': sum(x['tasks'] for x in report['runs'].values()),
                      'runs': {k: {f: v[f] for f in ['tasks', 'application_window_seconds', 'summed_task_seconds']}
                               for k,v in report['runs'].items()}}, ensure_ascii=False))
