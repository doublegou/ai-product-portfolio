"""Planning sensitivity model, NOT an estimator of historical DAU/MAU/retention.
The screenshot has no usage observations: the free parameters are assumptions.
Run: python3 estimate_scenarios.py
"""
import json
from pathlib import Path
p=Path(__file__).resolve().parent
s=json.loads((p/'source-record.json').read_text())['analytics']
n=s['first_time_downloads']; red=s['redownloads']; total=n+red
out={'label':'Planning scenarios, not observed user metrics or a confidence interval',
 'observed_derived':{'download_events':total,'redownload_share':red/total,'first_download_share':n/total},
 'population':'Hypothetical planning cohort of 72 first-download installation units, one unit per event; not distinct people or actual monthly acquisition',
 'assumptions':'Future 30-day active fraction and active days are deliberately varied, not inferred from screenshots or competitors. D7 is an independent return assumption, not derived from MAU.',
 'scenarios':[]}
for name,active,days,d7 in [('low',.2,2,.1),('middle',.4,4,.25),('high',.6,8,.4)]:
 out['scenarios'].append({'name':name,'assumed_30_day_active_fraction':active,'assumed_days_per_active_unit':days,'assumed_d7_return_fraction':d7,'expected_30_day_active_units':n*active,'expected_average_daily_active_units':n*active*days/30,'expected_day7_return_units':n*d7})
(p/'planning-scenarios.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(out,ensure_ascii=False,indent=2))
