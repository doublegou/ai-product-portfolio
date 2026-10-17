"""Recompute frozen Base V3 metrics from archived predictions; never retrain.

Run from any directory with Python 3 (standard library only). Reads full task,
pooled, site-mean and stress predictions, and verifies the two final LFS models.
Writes a compact metric report and deterministic diagnostic examples.
"""
from pathlib import Path
import csv
import hashlib
import json
import math
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src/river_sr'
BASE = SRC / 'training/base/v3'
RUN = BASE / 'runs/base_v3_full_20260817_r2'

def read(path):
    with path.open(newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def metrics(rows, prediction='predicted'):
    y = [float(r['observed']) for r in rows]
    pred = [float(r[prediction]) for r in rows]
    assert all(math.isfinite(v) for v in y + pred)
    errors = [p - o for p, o in zip(pred, y)]
    sse = sum(e * e for e in errors)
    mean = sum(y) / len(y)
    return dict(n=len(y), rmse=math.sqrt(sse / len(y)),
                mae=sum(abs(e) for e in errors) / len(y),
                bias=sum(errors) / len(y),
                r2=1-sse/sum((v-mean)**2 for v in y),
                extreme_n=sum(v >= .8 for v in y),
                extreme_hits=sum(o >= .8 and p >= .8 for o, p in zip(y, pred)))

def verify(actual, expected):
    for key in ('n', 'rmse', 'mae', 'bias', 'r2'):
        assert math.isclose(actual[key], float(expected[key]), rel_tol=1e-9, abs_tol=1e-12), (key, actual, expected)
    assert actual['extreme_hits'] == int(expected['hit_080_count'])

pool = read(RUN / 'reports/primary/pooled_outer_predictions.csv')
sites = read(RUN / 'reports/primary/site_oof_predictions.csv')
stress = read(RUN / 'reports/stress/pooled_predictions.csv')
index = {r['site_id']: r for r in read(BASE / 'folds/training_index.csv')}
folds = {(r['site_id'], r['repeat_id']): r for r in read(BASE / 'folds/outer_folds.csv')}
keys = {(r['model'], r['site_id'], r['repeat_id']): r for r in pool}
assert len(keys) == len(pool) == 33600
assert len(index) == 5600
assert len(sites) == len({(r['model'], r['site_id']) for r in sites}) == 11200
for r in pool:
    f = folds[r['site_id'], r['repeat_id']]
    assert (r['outer_fold'], r['hydro_system_id']) == (f['outer_fold'], f['hydro_system_id'])
    assert float(r['observed']) == float(index[r['site_id']]['sr87_sr86'])
# Check one held-out fold per complete hydrological system in each repeat.
system_folds = defaultdict(set)
for f in folds.values():
    system_folds[f['repeat_id'], f['hydro_system_id']].add(f['outer_fold'])
assert all(len(v) == 1 for v in system_folds.values())
for r in sites:
    preds = [float(keys[r['model'], r['site_id'], str(i)]['predicted']) for i in (1, 2, 3)]
    assert all(math.isclose(p, float(r[f'pred_repeat{i}']), abs_tol=1e-12) for i, p in enumerate(preds, 1))
    assert math.isclose(sum(preds)/3, float(r['pred_mean']), abs_tol=1e-12)
    assert float(r['observed']) == float(index[r['site_id']]['sr87_sr86'])
# Check every task's raw rows against the published pooled output.
raw_rows = []
for path in sorted((RUN / 'validation_tasks/primary').glob('repeat_*/fold_*/*/outer_predictions.csv')):
    raw_rows.extend(read(path))
assert len(raw_rows) == len(pool)
assert len({(r['model'],r['site_id'],r['repeat_id']) for r in raw_rows}) == len(pool)
for r in raw_rows:
    other = keys[r['model'], r['site_id'], r['repeat_id']]
    assert r == other, (r, other)
summary = {'primary_pooled': {}, 'primary_site_mean': {}, 'stress': {}, 'training': {}}
for mode, data, filename, pred in [
    ('primary_pooled', pool, 'primary_pooled_metrics.csv', 'predicted'),
    ('primary_site_mean', sites, 'primary_site_mean_metrics.csv', 'pred_mean')]:
    frozen = {r['model']: r for r in read(BASE / 'validation' / filename)}
    for model in ('rf', 'xgb'):
        subset = [r for r in data if r['model'] == model]
        m = metrics(subset, pred); verify(m, frozen[model]); summary[mode][model] = m
for frozen in read(BASE / 'validation/stress_scheme_metrics.csv'):
    subset = [r for r in stress if r['model'] == frozen['model'] and r['scheme'] == frozen['scheme']]
    assert len(subset) == len({r['site_id'] for r in subset}) == 5600
    m = metrics(subset); verify(m, frozen)
    summary['stress'][f"{frozen['model']}:{frozen['scheme']}"] = m
for frozen in read(BASE / 'release/training_metrics.csv'):
    model = frozen['model']; m = metrics(read(RUN / f'models/{model}_training_predictions.csv'))
    verify(m, frozen); summary['training'][model] = m
info = json.loads((BASE / 'release/release_info.json').read_text())
bundles = {}
for model, part, path in [('rf','selected_model',BASE/'release/model_bundle.rds'),
                          ('xgb','comparison_model',RUN/'models/xgb_final_bundle.rds')]:
    sha = digest(path); assert sha == info[part]['bundle_sha256'], f'LFS model missing or corrupted: {path}'
    bundles[model] = {'path':str(path.relative_to(ROOT)), 'bytes':path.stat().st_size, 'sha256':sha}
assert digest(RUN/'models/rf_final_bundle.rds') == bundles['rf']['sha256']
# Diagnostic examples use the middle-ranked absolute error in each fixed band.
# This is an evaluation replay, not independent validation or a real user story.
rf = [r for r in sites if r['model'] == 'rf']
total_sse = sum((float(r['pred_mean'])-float(r['observed']))**2 for r in rf)
bands = []; examples = []
for label, lo, hi in [('<0.72',0,.72),('0.72–0.75',.72,.75),('0.75–0.80',.75,.8),('≥0.80',.8,math.inf)]:
    group = [r for r in rf if lo <= float(r['observed']) < hi]
    m = metrics(group, 'pred_mean')
    m.update(band=label, sse_share=sum((float(r['pred_mean'])-float(r['observed']))**2 for r in group)/total_sse)
    bands.append(m)
    chosen = sorted(group, key=lambda r:(abs(float(r['pred_mean'])-float(r['observed'])), r['site_id']))[(len(group)-1)//2]
    meta = index[chosen['site_id']]
    examples.append(dict(band=label, site_id=chosen['site_id'], longitude=meta['longitude'], latitude=meta['latitude'],
        reference=meta['short_references'], observed=float(chosen['observed']), oof_mean=float(chosen['pred_mean']),
        absolute_error=abs(float(chosen['pred_mean'])-float(chosen['observed'])),
        pred_repeat1=float(chosen['pred_repeat1']), pred_repeat2=float(chosen['pred_repeat2']), pred_repeat3=float(chosen['pred_repeat3'])))
report = dict(scope='Metrics recomputed from archived predictions; no model retraining or fresh inference.',
              source_commit='ad120936a965608ba43794742b18d5caebe68b9d', run_id=RUN.name,
              rows=dict(primary=len(pool), site_mean=len(sites), stress=len(stress)),
              checks=dict(raw_tasks_equal_pooled=True, frozen_metrics_reproduced=True,
                          site_means_reproduced=True, held_out_system_identity=True, lfs_models_verified=True),
              metrics=summary, rf_bands=bands, model_bundles=bundles,
              examples_selection='Within each frozen observed band, lower middle absolute-error rank; site_id tie break.',
              sources=[{'path':str(p.relative_to(ROOT)),'sha256':digest(p)} for p in [RUN/'reports/primary/pooled_outer_predictions.csv',RUN/'reports/primary/site_oof_predictions.csv',RUN/'reports/stress/pooled_predictions.csv']], passed=True)
(ROOT/'evaluation/prediction-reproduction.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
with (ROOT/'demo/site-review.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(examples[0]),lineterminator="\n"); writer.writeheader();writer.writerows(examples)
print(json.dumps({'passed':True,'rows':report['rows'],'rf_bands':bands,'examples':examples},ensure_ascii=False,indent=2))
