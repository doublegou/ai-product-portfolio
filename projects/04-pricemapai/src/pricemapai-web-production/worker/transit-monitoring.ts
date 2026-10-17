import type {PublicMonitoring, TransitStation} from '../src/lib/apiTransit.ts';
type Obj = Record<string, any>;
const number = (v:unknown):number|null => typeof v==='number'&&Number.isFinite(v)&&v>=0?v:null;
const fraction = (v:unknown) => number(v)!=null&&Number(v)<=1?Number(v):null;
const percent = (v:unknown) => number(v)!=null&&Number(v)<=100?Number(v)/100:null;
const date = (v:unknown) => typeof v==='string'&&Number.isFinite(Date.parse(v))?new Date(v).toISOString():null;

/** Input rows are independent groups/models, never one copy per price variant. */
export function rollupMonitoring(rows:PublicMonitoring[], scope:string, sourceUrl:string):PublicMonitoring|undefined {
 const live=rows.filter(m=>!m.stale&&m.samples!==0&&(!m.updatedAt||Date.parse(m.updatedAt)>=Date.now()-86400000));
 if(!live.length)return;
 const rates=live.filter(m=>m.rate!=null), weighted=rates.length>0&&rates.every(m=>(m.samples??0)>0);
 const avg=(key:'rate'|'latencyMs'|'tokensPerSecond'|'cacheHitRate')=>{
  const values=live.filter(m=>m[key]!=null);if(!values.length)return null;
  const useWeights=values.every(m=>(m.samples??0)>0);
  return values.reduce((n,m)=>n+m[key]!*(useWeights?m.samples!:1),0)/values.reduce((n,m)=>n+(useWeights?m.samples!:1),0);
 };
 const aggregation=weighted?'按公开样本数加权':'按公开分组/模型等权；样本数未公开';
 return {rate:avg('rate'),samples:weighted?rates.reduce((n,m)=>n+m.samples!,0):null,
  latencyMs:avg('latencyMs'),latencyLabel:live.every(m=>m.latencyLabel===live[0].latencyLabel)?live[0].latencyLabel:'延迟',
  tokensPerSecond:avg('tokensPerSecond'),throughputLabel:live.find(m=>m.tokensPerSecond!=null)?.throughputLabel,
  cacheHitRate:avg('cacheHitRate'),scope,aggregation,sourceUrl,
  updatedAt:live.map(m=>m.updatedAt).filter((s):s is string=>!!s).sort().at(-1)??null,
  history:live.flatMap(m=>m.history).filter(p=>p.at).sort((a,b)=>a.at!.localeCompare(b.at!)).slice(-30)};
}

export function performanceSummary(raw:Obj, sourceUrl:string, at:string) {
 if(raw.success!==true||!Array.isArray(raw.data?.models))throw Error('原站未返回公开性能监测');
 const data=raw.data,updatedAt=number(data.window_end)!=null?new Date(data.window_end*1000).toISOString():at;
 const toMonitor=(row:Obj,scope:string):PublicMonitoring=>({rate:percent(row.success_rate),samples:number(row.request_count),
  latencyMs:number(row.avg_latency_ms),latencyLabel:'平均响应延迟',tokensPerSecond:number(row.avg_tps),throughputLabel:'平均生成速度',
  scope,sourceUrl,updatedAt,history:(Array.isArray(row.recent_success_series)?row.recent_success_series:[]).slice(-30).map((p:Obj)=>({rate:percent(p.success_rate),samples:null,at:typeof p.ts==='number'?new Date(p.ts*1000).toISOString():date(p.ts)}))});
 const models=new Map<string,PublicMonitoring>();
 for(const row of data.models)if(typeof row.model_name==='string')models.set(row.model_name,toMonitor(row,'模型（跨分组）· 24 小时'));
 const station=data.summary?toMonitor(data.summary,'全站 · 24 小时'):rollupMonitoring([...models.values()],`公开 ${models.size} 个模型汇总 · 24 小时`,sourceUrl);
 return {models,station};
}

export function attachPerformance(station:TransitStation,raw:Obj,sourceUrl:string,at:string) {
 const m=performanceSummary(raw,sourceUrl,at);
 if(m.station)station.publicMonitoring=m.station;
 for(const p of station.prices){const monitor=m.models.get(p.originalModel??p.standardModel??'');if(monitor)p.publicMonitoring=monitor;}
}

export function channelMonitorV2(row:Obj, sourceUrl:string, at:string, scope:string):PublicMonitoring|undefined {
 const m=row.metrics;if(!m)return;
 const health=row.health?.overall, hasSamples=health&&health!=='unknown';
 const checked=date(row.coverage?.data_through)??at;
 return {rate:hasSamples?fraction(m.success_rate):null,samples:number(m.request_count),latencyMs:number(m.ttft?.avg_ms),latencyLabel:'首字延迟',
  tokensPerSecond:number(m.tpm)==null?null:m.tpm/60,throughputLabel:'总 Token 吞吐',cacheHitRate:fraction(m.cache_rate),scope,sourceUrl,updatedAt:checked,
  history:(row.trend??[]).slice(-30).map((p:Obj)=>({rate:p.health?.overall==='unknown'?null:fraction(p.metrics?.success_rate),samples:number(p.metrics?.request_count),at:date(p.bucket_start)}))};
}
