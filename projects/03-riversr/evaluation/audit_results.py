"""Audit frozen summaries and population; does not refit or recreate raw OOF."""
import csv, hashlib, json, math
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'src/river_sr'
BASE = SRC / 'training/base/v3'
def rows(p):
    with p.open(newline='', encoding='utf-8-sig') as f: return list(csv.DictReader(f))
def indexed(p): return {r['model']:r for r in rows(p)}
def number(r,k): return float(r[k])
checks=[]
def check(name,passed):
    checks.append({'check':name,'passed':bool(passed)})
pop=rows(SRC/'data/processed/training/sr_full50_v2.csv')
bands=[sum(float(r['sr87_sr86'])<.72 for r in pop),sum(.72<=float(r['sr87_sr86'])<.75 for r in pop),sum(.75<=float(r['sr87_sr86'])<.8 for r in pop),sum(float(r['sr87_sr86'])>=.8 for r in pop)]
check('population_5600_unique_sites',len(pop)==5600 and len({r['site_id'] for r in pop})==5600)
check('observed_bands_match_frozen_design',bands==[4756,708,107,29])
manifest=json.loads((BASE/'validation/validation_manifest.json').read_text())
for f in manifest['files']:
    data=(SRC/f['path']).read_text().encode()
    check('sha256:'+Path(f['path']).name,hashlib.sha256(data).hexdigest()==f['sha256'])
pool=indexed(BASE/'validation/primary_pooled_metrics.csv'); site=indexed(BASE/'validation/primary_site_mean_metrics.csv'); train=indexed(BASE/'release/training_metrics.csv'); repeats=rows(BASE/'validation/primary_repeat_metrics.csv')
for model in ['rf','xgb']:
    rr=[r for r in repeats if r['model']==model]
    n=sum(number(r,'n') for r in rr)
    check(model+':pooled_population',n==16800 and number(pool[model],'n')==n)
    rmse=math.sqrt(sum(number(r,'rmse')**2*number(r,'n') for r in rr)/n)
    check(model+':pooled_rmse_from_repeat_summaries',math.isclose(rmse,number(pool[model],'rmse'),rel_tol=1e-10))
    check(model+':site_mean_population_and_extreme_hits',number(site[model],'n')==5600 and number(site[model],'hit_080_count')==0)
check('RF_lower_rmse_in_each_repeat',all(number(next(r for r in repeats if r['model']=='rf' and r['repeat_id']==str(i)),'rmse')<number(next(r for r in repeats if r['model']=='xgb' and r['repeat_id']==str(i)),'rmse') for i in range(1,4)))
result={'scope':'Frozen summary integrity, population recount and arithmetic; NOT raw-prediction metric reproduction or retraining.','run_id':manifest['source_run'],'population':{'sites':len(pop),'bands':dict(zip(['<0.72','0.72–0.75','0.75–0.80','>=0.80'],bands))},'rf_relative_rmse_reduction_percent':100*(1-number(pool['rf'],'rmse')/number(pool['xgb'],'rmse')),'rf_relative_mae_reduction_percent':100*(1-number(pool['rf'],'mae')/number(pool['xgb'],'mae')),'training_extreme_hits':{m:int(number(train[m],'hit_080_count')) for m in train},'checks':checks,'passed':all(c['passed'] for c in checks)}
(ROOT/'evaluation/results-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'passed':result['passed'],'checks':len(checks),'rmse_reduction_percent':result['rf_relative_rmse_reduction_percent']},ensure_ascii=False))
raise SystemExit(0 if result['passed'] else 1)
