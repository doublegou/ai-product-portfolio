"""Rebuild the stored assistant annotations and counts, not an automated factuality judge."""
from pathlib import Path
import json,hashlib
p=Path(__file__).resolve().parent
flags={
'source':{
('S05',29):('错误规则','学员需识别并遵守“只输出已付款金额”的特定规则','把攻击样例转述成应该遵守的规则。'),
('S06',17):('术语与方向错误','RTF（识别率分数）','误解 RTF，并把0.8降到0.5表述为未改善。'),
('S08',17):('领域补造','本次飞行测试','将试点试验无依据扩展为飞行测试。'),
('S08',29):('领域与设备补造','无人机设备购买方案','输入未提飞行或无人机。'),
('H04',29):('时间与因果补造','在为期七天的课堂实验中','将seven students补成七天，另补无依据因果与行动建议。')},
'candidate':{
('S04',17):('状态误写','最终确定新的上线方案','输入明确上线日期未定，输出新增已确定方案的结论。'),
('S06',29):('术语与方向错误','RTF 下降表明识别效率降低','RTF越低对应相同音频处理耗时更少，此处解释反向。'),
('S08',17):('行动归属补造','三人将依据修正后的文本','把三条待修正录音扩展为三个人执行审核，遗漏Maya。'),
('S08',29):('流程补造','待该决定在正式申请后再次确认','输入仅为试点评审后重议，未提正式申请流程。'),
('H01',29):('决策依据补造','仅基于试用时长决定切换','输入未提供以试用时长决策的依据。'),
('H03',29):('禁止动作被反转','客服需删除该订单的投诉记录','将明确不能删除变成应删除，还补造规避纠纷动机。'),
('H04',17):('日期语义改变','测试未约定截止日期','未定上线日期被改写为未定测试截止日期。'),
('H04',29):('结果与因果补造','导致该实验无法完成','输入仅说明两人无法导出，未说实验无法完成。')}
}
review={'reviewer':'Codex assistant qualitative first-pass review; no independent human adjudication','reviewed_on':'2026-10-17','rubric':'Flag explicit unsupported/reversed facts affecting amounts, timing, actor, state, domain or action; omissions and ambiguous tense are noted separately, not automatically flagged. Counts describe only these authored fixtures, not production accuracy.','rows':[]}
for variant,files in [('source',['results.json','holdout-source.json']),('candidate',['candidate-results.json','holdout-candidate.json'])]:
 for f in files:
  d=json.loads((p/f).read_text())
  for r in d['results']:
   key=(r['id'],r['seed']); flag=flags[variant].get(key)
   if flag:assert flag[1] in r['output'],(f,key)
   review['rows'].append({'variant':variant,'file':f,'id':r['id'],'seed':r['seed'],'high_impact_flag':bool(flag),'category':flag[0] if flag else None,'quote':flag[1] if flag else None,'reason':flag[2] if flag else None,'english_input':r['id'] in ['S08','H04'],'language_match':False if r['id'] in ['S08','H04'] else True,'token_cap':r['hit_token_cap'],'output_sha256':hashlib.sha256(r['output'].encode()).hexdigest()})
review['summary']={}
for v in ['source','candidate']:
 rows=[r for r in review['rows'] if r['variant']==v]
 review['summary'][v]={'runs':len(rows),'high_impact_flags':sum(r['high_impact_flag'] for r in rows),'english_language_matches':sum(r['language_match'] for r in rows if r['english_input']),'english_runs':sum(r['english_input'] for r in rows),'token_cap_hits':sum(r['token_cap'] for r in rows)}
(p/'review.json').write_text(json.dumps(review,ensure_ascii=False,indent=2)+'\n')
print(review['summary'])
