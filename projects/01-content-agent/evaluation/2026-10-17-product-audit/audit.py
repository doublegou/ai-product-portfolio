"""Offline product audit. Run using content-agent's installed Python dependencies.
Does not generate content, operate browsers, publish, or send email.
"""
from pathlib import Path
from collections import Counter, defaultdict
from datetime import datetime
import json, hashlib, struct, sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
AGENT = PROJECT / 'src/content-agent'
sys.path.insert(0, str(AGENT))
from src.create.review import find_quality_guard_issues

sources = {}
def read(path):
    sources[str(path.relative_to(PROJECT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return path.read_text()
def load(path): return json.loads(read(path))

def png(path, ratio):
    raw=path.read_bytes(); assert raw[:8] == b'\x89PNG\r\n\x1a\n'
    w,h=struct.unpack('>II',raw[16:24]);sources[str(path.relative_to(PROJECT))]=hashlib.sha256(raw).hexdigest()
    return dict(file=str(path.relative_to(PROJECT)),width=w,height=h,target_ratio=f'{ratio[0]}:{ratio[1]}',ratio_pass=w*ratio[1]==h*ratio[0])

rows=[]
log_paths=[AGENT/'data/logs'/name for name in ['2026-07-09.jsonl','2026-07-10.jsonl','2026-07-11.jsonl']]
for path in log_paths:
    rows.extend(json.loads(line) for line in read(path).splitlines() if line.strip())
groups=defaultdict(list)
for row in rows:
    groups[row['run_id']].append(row)
runs=[]
orphan_runs=[]
for rid,items in groups.items():
    starts=[x for x in items if x['event']=='run_start'];ends=[x for x in items if x['event']=='run_end']
    calls=[x for x in items if x['event']=='llm_call'];reviews=[x for x in items if x['event']=='review_round']
    collections=[x for x in items if x['event']=='xhs_strategy_collection_completed']
    if not starts:
        orphan_runs.append(dict(run_id=rid,event_count=len(items),events=dict(Counter(x['event'] for x in items))))
        continue
    assert len(starts)==1 and len(ends)<=1 and len(collections)<=1, rid
    known=[x for x in calls if all(isinstance(x.get(k),int) for k in ['prompt_tokens','completion_tokens','total_tokens'])]
    for x in known: assert x['prompt_tokens']+x['completion_tokens']==x['total_tokens']
    runs.append(dict(run_id=rid,command=starts[0]['command'],start=starts[0]['ts'],has_end=bool(ends),
        recorded_status=ends[0]['status'] if ends else 'unknown_no_run_end',
        elapsed_seconds=round(ends[0]['duration_ms']/1000,3) if ends else None,
        llm_calls=len(calls),llm_success=sum(x['success'] for x in calls),
        llm_seconds=round(sum(x['duration_ms'] for x in calls)/1000,3),
        calls_with_token_usage=len(known),prompt_tokens_known=sum(x['prompt_tokens'] for x in known),
        completion_tokens_known=sum(x['completion_tokens'] for x in known),total_tokens_known=sum(x['total_tokens'] for x in known),
        token_coverage_complete=bool(calls) and len(calls)==len(known),
        review_rounds=len(reviews),review_pass_events=sum(x['passed'] is True for x in reviews),
        collection_summary={k:collections[0][k] for k in ['collected_creators','collected_notes','target_creators']} if collections else None,
        labels=dict(Counter(x['label'] for x in calls))))
strategy=[x for x in runs if x['command']=='strategy_collect']; reported=[x for x in strategy if x['collection_summary'] is not None]
fixtures=load(HERE/'guard-cases.json')['cases'];guard=[]
for case in fixtures:
    issues=find_quality_guard_issues({'product':'BirdTracker','body':case['text']})
    guard.append({**case,'actual_flag':bool(issues),'matches_expected':bool(issues)==case['should_flag'],'issues':issues})
mat={name:sum((x['should_flag'],x['actual_flag'])==pair for x in guard) for name,pair in {'true_positive':(True,True),'false_negative':(True,False),'true_negative':(False,False),'false_positive':(False,True)}.items()}
card_dir=PROJECT/'demo/content-workflow/2026-08-27-literature-review/generated-originals'
cards=[png(p,(3,4)) for p in sorted(card_dir.glob('*.png'))]
cover_dir=PROJECT/'demo/script-workflow/2026-09-26-agentic-video/artifacts/post/005'
covers=[png(cover_dir/name,ratio) for name,ratio in [('3-4.png',(3,4)),('4-3.png',(4,3)),('16-9.png',(16,9))]]
radar=load(PROJECT/'demo/daily-trend-radar/2026-10-16-source-check/report-proxy.json')
full=next(x for x in runs if x['run_id']=='20260709-131559-330e67')
stages=[]
for label in ['Topic discovery planner','Research analyzer','Writer','Reviewer','Editor']:
    stage_calls=[x for x in groups[full['run_id']] if x['event']=='llm_call' and x['label']==label]
    stages.append(dict(label=label,calls=len(stage_calls),prompt_tokens=sum(x['prompt_tokens'] for x in stage_calls),
        completion_tokens=sum(x['completion_tokens'] for x in stage_calls),
        seconds=round(sum(x['duration_ms'] for x in stage_calls)/1000,3)))
assert sum(x['calls'] for x in stages)==full['llm_calls']
assert sum(x['prompt_tokens']+x['completion_tokens'] for x in stages)==full['total_tokens_known']
# Bind the rule implementation, its factual reference and the audit itself to this result.
for path in [AGENT/'src/create/review.py',AGENT/'memory/products/birdtracker.md',Path(__file__)]:
    read(path)
# Hypothetical prices; no claim about any provider's actual or current tariff.
estimates=[dict(assumed_input_yuan_per_million=i,assumed_output_yuan_per_million=o,estimated_llm_yuan=round((full['prompt_tokens_known']*i+full['completion_tokens_known']*o)/1_000_000,6)) for i,o in [(1,4),(5,20),(10,40)]]
out=dict(evaluated_on='2026-10-17',scope='offline historical audit + newly executed deterministic guard probes; no live model run',
    historical=dict(log_files=len(log_paths),event_count=len(rows),runs=runs,orphan_runs_without_start=orphan_runs,
      daily_started=sum(x['command']=='daily' for x in runs),daily_with_end=sum(x['command']=='daily' and x['has_end'] for x in runs),
      strategy_started=len(strategy),strategy_success_labels=sum(x['recorded_status']=='success' for x in strategy),
      strategy_with_collection_summary=len(reported),strategy_zero_creators_and_notes=sum(x['collection_summary']['collected_creators']==0 and x['collection_summary']['collected_notes']==0 for x in reported),
      strategy_with_notes=sum(x['collection_summary']['collected_notes']>0 for x in reported)),
    guard=dict(sample_origin='constructed, deliberately probes known boundary classes; not representative production distribution; expectations not independently adjudicated',cases=guard,confusion=mat,matched=sum(x['matches_expected'] for x in guard),total=len(guard)),
    artifacts=dict(cards=cards,covers=covers,radar=dict(items=len(radar['items']),sources=len(radar['sourceStatus']),missing_published_at=sum(x.get('publishedAt') is None for x in radar['items']))),
    complete_usage_stage_breakdown=dict(run_id=full['run_id'],stages=stages),
    estimates=dict(kind='sensitivity illustration only; hypothetical unit prices, not an invoice or measured cost',run_id=full['run_id'],scenarios=estimates,excludes=['images','collection operations','human review','failed prior runs','other platform fees']),source_sha256=sources)
(HERE/'results.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:out[k] for k in ['evaluated_on','scope']},ensure_ascii=False))
print('Guard:',mat,'matches',out['guard']['matched'],'/',len(guard))
print('Complete usage run:',json.dumps(full,ensure_ascii=False))
print('Strategy:',{k:v for k,v in out['historical'].items() if k.startswith('strategy')})
