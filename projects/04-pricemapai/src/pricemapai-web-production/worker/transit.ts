import { assertRobots, download, readLimited, safeUrl } from './network.ts';
import type { TransitStation, TransitPrice, PublicMonitoring } from '../src/lib/apiTransit.ts';
import {attachPerformance, rollupMonitoring, channelMonitorV2} from './transit-monitoring.ts';

export interface TransitSource {
  id: string; name: string; base_url: string; collector: 'transit' | 'newapi' | 'zivv' | 'onehop' | 'public_models';
  config: { snapshot_url: string; pricing_url: string; website_url?: string; monitor_url?: string; monitor_kind?: 'performance'|'zivv'|'channel_v2'; availability_unit?: 'fraction'|'percent'; request_timeout_seconds?:number };
  interval_minutes: number; enabled: boolean; adaptive_enabled?: boolean; lease_token?: string;
}
type Obj = Record<string, any>;
const obj = (v: unknown): Obj => v && typeof v === 'object' && !Array.isArray(v) ? v : {};
const arr = (v: unknown): Obj[] => Array.isArray(v) ? v.map(obj) : [];
const str = (v: unknown) => typeof v === 'string' && v.trim() ? v.trim().slice(0,1500) : null;
const num = (v: unknown): number | null => typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null;
const fraction = (v: unknown) => num(v) != null && Number(v) <= 1 ? Number(v) : null;
const percentage = (v: unknown) => num(v) != null && Number(v) <= 100 ? Number(v)/100 : null;
const timestamp = (v: unknown) => typeof v==='string' && Number.isFinite(Date.parse(v)) ? new Date(v).toISOString() : null;
const textList = (v: unknown) => Array.isArray(v) ? v.map(str).filter((x): x is string => !!x) : [];
function publicUrl(value: unknown, fallback: string | null = null) { try { return typeof value==='string' ? safeUrl(value).href : fallback; } catch { return fallback; } }
export function modelFamily(model: string, platform = ''): string | null {
  const m=model.toLowerCase();
  if(/(?:image|imagen|flux|dall-e|midjourney|seedream|stable-diffusion)/.test(m))return 'image';
  if(/(?:sora|veo|kling|seedance|wan[._-]|video|vidu|hailuo)/.test(m))return 'video';
  if(/claude/.test(m))return 'claude'; if(/gpt|codex|^o[134](?:-|$)/.test(m))return 'gpt';
  if(/gemini/.test(m))return 'gemini';if(/grok/.test(m))return 'grok';if(/deepseek/.test(m))return 'deepseek';
  if(/kimi|moonshot/.test(m))return 'kimi';if(/qwen|qwq/.test(m))return 'qwen';if(/glm/.test(m))return 'glm';
  if(/mimo/.test(m))return 'mimo';if(/doubao/.test(m))return 'doubao';if(/minimax/.test(m))return 'minimax';if(/hunyuan/.test(m))return 'hunyuan';
  return ({anthropic:'claude',openai:'gpt',gemini:'gemini',google:'gemini',grok:'grok'} as Record<string,string>)[platform.toLowerCase()] ?? null;
}
function sourceChannel(s: Obj): string {
  if(s.is_mixed===true||/mixed/.test(s.upstream_type??'')||/mixed/.test(s.account_pool_type??''))return 'mixed';
  if(s.is_reverse===true||/reverse/.test(s.upstream_type??''))return 'reverse_engineered';
  if(/self_hosted|first_party/.test(s.account_pool_type??''))return 'first_party_pool';
  if(/official_api|official_key/.test(s.upstream_type??''))return 'official_api';
  if(/resell/.test(s.upstream_type??''))return 'reseller';
  if(/cloud/.test(s.upstream_type??''))return 'cloud';
  return 'undisclosed';
}
export function billingConversion(b: Obj) {
  const raw=str(b.recharge_ratio), currency=str(b.currency), credit=str(b.credit_currency);
  const match=raw?.match(/^(\d+(?:\.\d+)?)\s*(CNY|USD|RMB|元)\s*=\s*(\d+(?:\.\d+)?)\s*(USD|CNY)/i);
  let paid: number|undefined, balance: number|undefined, paidCurrency: string|undefined, balanceCurrency: string|undefined;
  if(match){paid=Number(match[1]);balance=Number(match[3]);paidCurrency=/RMB|元/i.test(match[2])?'CNY':match[2].toUpperCase();balanceCurrency=match[4].toUpperCase();}
  else if(raw?.match(/^(\d+(?:\.\d+)?) USD balance per (\d+(?:\.\d+)?) CNY$/i)){const m=raw.match(/^(\d+(?:\.\d+)?) USD balance per (\d+(?:\.\d+)?) CNY$/i)!;paid=Number(m[2]);balance=Number(m[1]);paidCurrency='CNY';balanceCurrency='USD';}
  else {const colon=raw?.match(/^(\d+(?:\.\d+)?)\s*:\s*(\d+(?:\.\d+)?)$/);if(colon&&currency==='CNY'&&credit==='USD'){paid=Number(colon[1]);balance=Number(colon[2]);paidCurrency=currency;balanceCurrency=credit;}}
  const valid=paid!=null&&paid>0&&balance!=null&&balance>0&&paidCurrency===currency&&balanceCurrency===credit&&credit==='USD';
  return {ratio:raw,factor:valid?paid!/balance!:null,currency:valid?paidCurrency!:'USD_CREDIT',rechargeCurrency:currency,creditCurrency:credit,conflict:!!match&&!valid};
}
function passiveMonitor(row: Obj, scope: string, snapshot: Obj, sourceUrl: string): PublicMonitoring|undefined {
  const samples=num(row.request_count);if(!samples)return;
  const metrics=obj(row.metrics),ttft=obj(metrics.ttft);
  return {rate:fraction(row.success_rate)??fraction(metrics.success_rate),samples,
    latencyMs:num(row.avg_ttft_ms)??num(ttft.avg_ms),latencyLabel:'首字延迟',scope,
    sourceUrl,updatedAt:timestamp(row.last_request_at)??timestamp(snapshot.generated_at),
    tokensPerSecond:num(metrics.tpm)==null?null:metrics.tpm/60,throughputLabel:'总 Token 吞吐',cacheHitRate:fraction(row.cache_hit_rate)??fraction(metrics.cache_rate),
    history:arr(row.buckets).slice(-30).map(p=>({rate:num(p.request_count)?fraction(p.success_rate):null,samples:num(p.request_count),at:timestamp(p.start)}))};
}
function activeMonitor(row: Obj, model: string, scope: string, sourceUrl: string): PublicMonitoring|undefined {
  if(!Object.keys(row).length)return;
  const modelRow=arr(row.models).find(m=>(m.model??'').toLowerCase()===model.toLowerCase());
  const selected=modelRow??row, days=num(selected.availability_1d)!=null?1:7;
  const rate=percentage(selected[`availability_${days}d`]);
  const samples=num(selected[`sample_count_${days}d`])??num(row[`sample_count_${days}d`]);
  const modelScope=!!modelRow||row.primary_model?.toLowerCase()===model.toLowerCase();
  const label=modelScope?`模型探测 · ${days} 天`:`${scope}探测（${str(row.primary_model)??'公开模型'}）· ${days} 天`;
  const history=(!modelRow||row.primary_model?.toLowerCase()===model.toLowerCase()?arr(row.timeline):[])
    .map(p=>({rate:['operational','up','healthy','success'].includes(p.status)?1:['down','error','failed'].includes(p.status)?0:null,samples:1,at:timestamp(p.checked_at)}))
    .sort((a,b)=>(a.at??'').localeCompare(b.at??'')).slice(-30);
  if(rate==null&&!history.length)return;
  if(rate===0&&samples==null&&!history.length&&!timestamp(row.last_checked_at)&&!row.primary_status)return;
  return {rate:samples===0?null:rate,samples,latencyMs:row.response_latency_public===false?null:num(selected[`avg_latency_${days}d_ms`]),latencyLabel:'探测延迟',scope:label,sourceUrl,updatedAt:timestamp(row.last_checked_at),history};
}
function cacheUsage(group: Obj) {
  if(group.cache_usage_public===false)return null;
  const c=obj(obj(group.cache_usage).last_24h), samples=(num(c.input_tokens)??0)+(num(c.cache_creation_tokens)??0)+(num(c.cache_read_tokens)??0);
  const hit=percentage(c.cache_hit_rate);return samples>0&&hit!=null?{hitRate:hit,sampleTokens:samples}:null;
}
const blankPrice = (): TransitPrice => ({family:null,standardModel:null,groupName:null,rechargeRatio:null,modelMultiplier:null,fixedPrice:null,fixedPriceUnit:null,inputPrice:null,outputPrice:null,currency:null,accountPool:null,channelType:'undisclosed',lastVerifiedAt:null,sevenDayRate:null,sevenDaySamples:null,note:null,sourceLabel:'商家原站公开报价',sourceUrl:null,requestWindowHours:null});
function stationBase(source: TransitSource, at: string): TransitStation {
  return {id:source.id,name:source.name,websiteUrl:publicUrl(source.config.website_url,source.base_url),pricingUrl:source.config.pricing_url,summary:null,channelTypes:['undisclosed'],lastUpdatedAt:at,prices:[]};
}
export function normalizeTransit(raw: unknown, source: TransitSource, at=new Date().toISOString()): TransitStation {
  const d=obj(raw);if(!Array.isArray(d.groups)||!str(d.schema_version)?.startsWith('ai-transit.'))throw Error('原站未返回可识别的公开报价快照');
  const station=stationBase(source,at),meta=obj(d.station),billing=obj(d.billing),conversion=billingConversion(billing),passive=obj(d.passive_monitoring);
  station.name=str(meta.name)??source.name;
  station.pricingUrl=publicUrl(meta.price_url,source.config.pricing_url)!;
  station.monitorUrl=publicUrl(meta.monitor_url,station.pricingUrl);
  station.sourceUpdatedAt=timestamp(d.generated_at);
  station.info={minimumTopUp:num(billing.minimum_top_up)!=null?`${billing.minimum_top_up} ${str(billing.currency)??''}`:null,stationSystem:str(d.system),invoiceSupport:null,operatorType:null,refundPolicy:typeof billing.refund_policy==='string'?str(billing.refund_policy):null,balanceExpiry:typeof billing.balance_expiry==='string'?str(billing.balance_expiry):null,paymentMethods:textList(billing.payment_methods),supportChannels:str(meta.support_url)?[str(meta.support_url)!]:[]};
  const window=obj(passive.window),period=str(window.period)==='last_7d'?'7 天':'24 小时';
  station.publicMonitoring=passive.enabled===true?passiveMonitor(window,`全站 · ${period}`,d,station.monitorUrl!):undefined;
  const monitors:Obj[]=arr(d.monitoring).map(m=>({...m,models:arr(m.models).map(row=>({...row}))}));
  if(source.config.availability_unit==='fraction')for(const m of monitors)for(const row of [m,...arr(m.models)])for(const key of ['availability_1d','availability_7d','availability_15d','availability_30d'])if(fraction(row[key])!=null)row[key]*=100;
  if(!station.publicMonitoring){
    // Aggregate each original group once, before expanding it into model/spec prices.
    const unique=new Map(monitors.map(m=>[str(m.group_name)??str(m.name),m]));
    const groups=[...unique.values()].map(m=>activeMonitor(m,str(m.primary_model)??'','分组',station.monitorUrl!)).filter((m):m is PublicMonitoring=>!!m);
    const days=groups[0]?.scope.match(/· (\d+) 天/)?.[1];
    station.publicMonitoring=rollupMonitoring(groups.filter(m=>m.scope.endsWith(`· ${days} 天`)),`公开 ${groups.length} 项监测汇总 · ${days??7} 天`,station.monitorUrl!);
  }
  for(const group of arr(d.groups)) {
    const groupName=str(group.name);if(!groupName)continue;
    const rate=num(group.rate_multiplier),applied=billing.group_multiplier_applied===true||group.group_multiplier_applied===true;
    const groupMonitor=monitors.find(m=>(m.group_name??m.name)===groupName)??{};
    const passiveGroup=arr(passive.groups).find(g=>(g.name??g.group_name)===groupName)??{};
    for(const model of arr(group.models)) {
      const name=str(model.standard_model)??str(model.raw_model);if(!name)continue;
      const p=obj(model.price),mode=str(model.billing_mode)??'unknown';
      const tiered=arr(model.intervals).length>1||/tier|expr/.test(mode);
      const groupFactor=applied?1:rate;
      const effective=groupFactor==null?null:groupFactor*(conversion.factor??1);
      const note=[tiered?'阶梯计费，具体档位请查看原站':null,conversion.conflict?'原站充值币种字段不一致，暂按计价额度展示':null,applied?'原价已包含分组倍率':null,str(model.source?.disclosure),str(model.description)].filter(Boolean).join('；');
      const usdValue=(v:unknown)=>!tiered&&effective!=null&&num(v)!=null?Number(v)*effective:null;
      const passiveModel=arr(passive.models).find(m=>m.group_name===groupName&&[name,model.raw_model].includes(m.model))??{};
      const monitor=passive.enabled===true?(passiveMonitor(passiveModel,`模型 · ${period}`,d,station.monitorUrl!)??passiveMonitor(passiveGroup,`分组 · ${period}`,d,station.monitorUrl!)):undefined;
      const price:TransitPrice={...blankPrice(),family:modelFamily(name,str(model.platform)??str(group.platform)??''),standardModel:name,originalModel:str(model.raw_model)??name,groupName,rechargeRatio:conversion.ratio,rechargeCurrency:conversion.rechargeCurrency,creditCurrency:conversion.creditCurrency,modelMultiplier:rate,
        comparisonEligible:!tiered&&!conversion.conflict&&conversion.currency==='CNY'&&!applied,
        currency:conversion.currency,inputPrice:usdValue(p.input_usd_per_token)==null?null:usdValue(p.input_usd_per_token)!*1e6,outputPrice:usdValue(p.output_usd_per_token)==null?null:usdValue(p.output_usd_per_token)!*1e6,
        billingMode:tiered?'tiered':mode,priceBasis:applied?'group_applied':'group_multiplier',channelType:sourceChannel(obj(model.source)),accountPool:str(model.source?.account_pool_type),cacheUsage:cacheUsage(group),
        lastVerifiedAt:at,sourceUpdatedAt:station.sourceUpdatedAt,sourceUrl:station.pricingUrl,note:note||null,publicMonitoring:monitor??activeMonitor(groupMonitor,name,'分组',station.monitorUrl!)};
      if(['per_request','per_image','per_second'].includes(mode)) {
        price.fixedPrice=usdValue(p.per_request_usd??p.per_image_usd??p.per_second_usd);
        price.fixedPriceUnit=mode==='per_second'?'second':mode==='per_image'?'image':'request';
        if(p.image_size_prices&&Object.keys(obj(p.image_size_prices)).length){for(const [size,value] of Object.entries(obj(p.image_size_prices))){station.prices.push({...price,groupName:`${groupName} · ${size}`,fixedPrice:usdValue(value),fixedPriceUnit:'image',id:JSON.stringify([groupName,name,size])});}continue;}
      }
      price.id=JSON.stringify([groupName,name,mode]);station.prices.push(price);
    }
  }
  station.channelTypes=[...new Set(station.prices.map(p=>p.channelType??'undisclosed'))];
  return validateStation(station);
}
export function normalizeNewApi(raw: unknown, source: TransitSource, at=new Date().toISOString()): TransitStation {
  const d=obj(raw);if(d.success!==true||!Array.isArray(d.data))throw Error('原站未返回 New API 公开价格');
  const station=stationBase(source,at);station.info={minimumTopUp:null,stationSystem:'new_api',invoiceSupport:null,operatorType:null,refundPolicy:null,balanceExpiry:null,paymentMethods:[],supportChannels:[]};
  for(const model of arr(d.data)) {
    const name=str(model.model_name);if(!name)continue;
    for(const group of textList(model.enable_groups)){
      const ratio=num(obj(d.group_ratio)[group]);if(ratio==null)continue;
      const groupBilling=obj(obj(model.group_billing)[group]);
      const tiered=model.billing_mode==='tiered_expr'||!!model.billing_expr||groupBilling.billing_mode==='tiered_expr'||!!groupBilling.billing_expr;
      const perRequest=model.quota_type===1;
      const input=!tiered&&!perRequest&&num(model.model_ratio)!=null?Number(model.model_ratio)*2*ratio:null;
      station.prices.push({...blankPrice(),id:JSON.stringify([group,name]),standardModel:name,originalModel:name,groupName:group,family:modelFamily(name),modelMultiplier:null,
        fixedPrice:!tiered&&perRequest&&num(model.model_price)!=null?model.model_price*ratio:null,fixedPriceUnit:perRequest?'request':null,
        inputPrice:input,outputPrice:input!=null&&num(model.completion_ratio)!=null?input*model.completion_ratio:null,currency:'USD_CREDIT',comparisonEligible:false,
        billingMode:tiered?'tiered':perRequest?'per_request':'token',priceBasis:'group_applied',lastVerifiedAt:at,sourceUrl:source.config.pricing_url,
        note:tiered?'原站使用阶梯计费表达式，具体价格请查看原站':'按原站 USD 计价额度展示，已包含分组倍率；未公开充值换算，不折算人民币'});
    }
  }
  return validateStation(station);
}
const decimal = (v:unknown) => typeof v==='string'&&/^\d+(\.\d+)?$/.test(v)?Number(v):num(v);
export function normalizeZivv(raw:unknown,source:TransitSource,at=new Date().toISOString()) {
 const d=obj(raw);if(!Array.isArray(d.data))throw Error('原站未返回模型广场');
 const station=stationBase(source,at);
 for(const model of arr(d.data))for(const group of arr(model.groups)){
  const name=str(model.id),groupName=str(group.name);if(!name||!groupName)continue;
  const family=modelFamily(name,str(model.provider)??'');
  const p:TransitPrice={...blankPrice(),standardModel:name,originalModel:name,family,groupName,currency:'USD_CREDIT',lastVerifiedAt:at,sourceUrl:source.config.pricing_url,comparisonEligible:false,
   inputPrice:num(group.input_rate),outputPrice:num(group.output_rate),billingMode:'token',priceBasis:'group_applied',note:'原站公开分组价格，已包含分组系数；按 USD 计价额度展示'};
  const specs=Object.entries(group).filter(([key,value])=>/^(image_rate_[124]k|video_rate_(720|1080)p)$/.test(key)&&(num(value)??0)>0);
  if(specs.length){for(const [spec,cost] of specs)station.prices.push({...p,id:JSON.stringify([groupName,name,spec]),groupName:`${groupName} · ${spec.replace(/^(image|video)_rate_/,'')}`,fixedPrice:Number(cost),fixedPriceUnit:spec.startsWith('image')?'image':'request',inputPrice:null,outputPrice:null,billingMode:'per_request'});}
  else if((num(group.fixed_price)??0)>0)station.prices.push({...p,id:JSON.stringify([groupName,name]),fixedPrice:group.fixed_price,fixedPriceUnit:family==='image'?'image':'request',inputPrice:null,outputPrice:null,billingMode:'per_request'});
  else station.prices.push({...p,id:JSON.stringify([groupName,name])});
 }
 return validateStation(station);
}
export function normalizeOnehop(raw:unknown,source:TransitSource,at=new Date().toISOString()) {
 const d=obj(obj(raw).data);if(!Array.isArray(d.items))throw Error('原站未返回公开模型目录');
 if(d.nextCursor)throw Error('原站模型目录仍有下一页，禁止写入不完整报价');
 const station=stationBase(source,at),monitors:PublicMonitoring[]=[];
 for(const model of arr(d.items)){
  const name=str(model.fullSlug);if(!name)continue;
  const metrics=obj(model.displayMetrics),history=arr(metrics.uptime24h).map(p=>({rate:fraction(p.rate),samples:null,at:timestamp(p.hour)}));
  const monitor:PublicMonitoring={rate:fraction(metrics.successRate),samples:null,latencyMs:null,latencyLabel:'延迟',scope:'模型 · 原站近况',sourceUrl:source.config.pricing_url,updatedAt:history.map(p=>p.at).filter((s):s is string=>!!s).sort().at(-1)??at,history};
  if(monitor.rate!=null)monitors.push(monitor);
  const tiered=arr(model.tokenPricingBands).length>1||model.videoPrice?.tiered===true||arr(model.imageTiers).length>1;
  const fixed=decimal(model.imagePerCallPrice)??decimal(model.videoPrice?.amount);
  station.prices.push({...blankPrice(),id:name,standardModel:str(model.upstreamModelId)??name,originalModel:str(model.upstreamModelId)??name,groupName:str(model.source),family:modelFamily(name),
   currency:'USD_CREDIT',inputPrice:tiered?null:decimal(model.inputPricePer1m),outputPrice:tiered?null:decimal(model.outputPricePer1m),fixedPrice:tiered?null:fixed,fixedPriceUnit:model.videoPrice?.unit==='per_second'?'second':model.imagePerCallPrice?'image':'request',
   billingMode:tiered?'tiered':fixed!=null?'per_request':'token',comparisonEligible:false,priceBasis:'group_applied',lastVerifiedAt:at,sourceUrl:source.config.pricing_url,publicMonitoring:monitor,
   channelType:model.source==='Official'?'official_api':'undisclosed',note:tiered?'阶梯计费，具体档位请查看原站':'原站公开目录价格；按 USD 计价额度展示，未折算人民币'});
 }
 station.publicMonitoring=rollupMonitoring(monitors,`公开 ${monitors.length} 个模型汇总 · 原站近况`,source.config.pricing_url);
 return validateStation(station);
}
export function normalizePublicModels(raw:unknown,source:TransitSource,at=new Date().toISOString()) {
 const d=obj(obj(raw).data);if(!Array.isArray(d.models))throw Error('原站未返回公开模型价格');
 const station=stationBase(source,at);
 for(const model of arr(d.models)){
  const name=str(model.name),p=obj(model.pricing);if(!name||!Object.keys(p).length)continue;
  const mode=str(p.billing_mode)??'token',tiered=arr(p.intervals).length>1;
  station.prices.push({...blankPrice(),id:name,standardModel:name,originalModel:name,family:modelFamily(name,str(model.platform)??''),groupName:'公开目录基准价',currency:'USD_CREDIT',
   inputPrice:!tiered&&num(p.input_price)!=null?p.input_price*1e6:null,outputPrice:!tiered&&num(p.output_price)!=null?p.output_price*1e6:null,
   fixedPrice:tiered?null:num(p.per_request_price),fixedPriceUnit:'request',billingMode:tiered?'tiered':mode,comparisonEligible:false,priceBasis:'catalog_base',sourceUrl:source.config.pricing_url,lastVerifiedAt:at,
   note:tiered?'阶梯计费，具体档位请查看原站':'原站公开模型目录基准价；实际分组倍率与充值规则请在原站核对'});
 }
 return validateStation(station);
}
export function attachZivvStatus(station:TransitStation,raw:unknown,url:string,at:string) {
 const d=obj(raw);if(!Array.isArray(d.services))throw Error('原站未返回公开渠道状态');
 const monitors=new Map<string,PublicMonitoring>();
 for(const s of arr(d.services)){
  const points=arr(s.history).filter(p=>typeof p.ok==='boolean'),samples=points.length;
  const latencies=points.filter(p=>p.ok&&num(p.latency_ms)!=null);
  monitors.set(s.name,{rate:samples?points.filter(p=>p.ok).length/samples:percentage(s.uptime_percent),samples:samples||null,latencyMs:latencies.length?latencies.reduce((n,p)=>n+p.latency_ms,0)/latencies.length:null,latencyLabel:'探测延迟',scope:`分组探测（${str(s.model)??'公开模型'}）· 原站返回窗口`,sourceUrl:url,updatedAt:timestamp(d.checked_at)??at,
   history:points.slice(-30).map(p=>({rate:p.ok?1:0,samples:1,at:timestamp(p.timestamp)}))});
 }
 station.publicMonitoring=rollupMonitoring([...monitors.values()],`公开 ${monitors.size} 个分组汇总 · 原站返回窗口`,url);
 for(const p of station.prices){const m=monitors.get(p.groupName?.split(' · ')[0]??'');if(m)p.publicMonitoring=m;}
}
function validateStation(station: TransitStation) {
  if(!station.prices.length)throw Error('原站报价列表为空，保留上次成功数据');
  if(station.prices.length>5000)throw Error('原站报价超过单站处理上限，等待适配');
  const keys=station.prices.map(p=>p.id);if(new Set(keys).size!==keys.length)throw Error('原站存在重复模型/分组，等待核验');
  return station;
}
export async function collectTransit(source: TransitSource) {
  const endpoint=safeUrl(source.config.snapshot_url),base=safeUrl(source.base_url);
  if(endpoint.origin!==base.origin)throw Error('采集接口须与来源地址同域');
  const raw=await readPublicFeed(endpoint.href,source.config.request_timeout_seconds),at=new Date().toISOString();
  const normalize={transit:normalizeTransit,newapi:normalizeNewApi,zivv:normalizeZivv,onehop:normalizeOnehop,public_models:normalizePublicModels}[source.collector];
  const station=normalize(raw,source,at);
  if(source.config.monitor_url)try{
    const monitoring=obj(await readPublicFeed(source.config.monitor_url));
    if(source.config.monitor_kind==='performance')attachPerformance(station,monitoring,source.config.monitor_url,at);
    else if(source.config.monitor_kind==='zivv')attachZivvStatus(station,monitoring,source.config.monitor_url,at);
    else if(source.config.monitor_kind==='channel_v2'){
      station.publicMonitoring=channelMonitorV2(obj(monitoring.monitoring),source.config.monitor_url,at,'全站 · 7 天');
      for(const p of station.prices){const row=arr(monitoring.models).find(m=>m.model===p.standardModel);if(row)p.publicMonitoring=channelMonitorV2(row,source.config.monitor_url,timestamp(monitoring.generated_at)??at,'模型（跨分组）· 7 天');}
    }
  }catch(e){station.monitoringError=e instanceof Error?e.message:'监测接口暂不可用';}
  return station;
}

// These are anonymous, documented public data feeds, separate from HTML crawling.
// Generic search-engine /api/ exclusions must not disable an advertised integration.
// All other paths still go through robots; no cookies, keys or private API paths are used.
const PUBLIC_FEED_PATH=/^(?:\/api\/public\/transit\/(?:v[12]\/)?snapshot|\/api\/pricing|\/api\/perf-metrics\/summary|\/api\/models\/hub|\/api\/status|\/public\/models|\/api\/v1\/models\/public)$/;
async function readPublicFeed(url:string,timeout=35):Promise<unknown> {
 const endpoint=safeUrl(url);
 if(!PUBLIC_FEED_PATH.test(endpoint.pathname))await assertRobots(endpoint.origin,[endpoint.pathname]);
 const response=await download(endpoint.href,{signal:AbortSignal.timeout(Math.max(10,Math.min(60,timeout))*1000)},endpoint.origin);
 try{return JSON.parse(await readLimited(response));}catch(e){if(e instanceof SyntaxError)throw Error('原站未返回 JSON 报价，可能为验证页或接口已变更');throw e;}
}

export function validateTransitSource(raw:unknown): Omit<TransitSource,'id'> {
 const b=obj(raw),base=safeUrl(b.base_url),config=obj(b.config);
 if(!['transit','newapi','zivv','onehop','public_models'].includes(b.collector)||typeof b.name!=='string'||!b.name.trim()||b.name.length>100)throw Error('请填写来源名称与采集器类型');
 const interval=b.interval_minutes??15;
 if(!Number.isInteger(interval)||interval<10||interval>10080)throw Error('采集间隔须为 10–10080 分钟');
 if(b.enabled!==undefined&&typeof b.enabled!=='boolean')throw Error('enabled 必须为布尔值');
 if(b.adaptive_enabled!==undefined&&typeof b.adaptive_enabled!=='boolean')throw Error('adaptive_enabled 必须为布尔值');
 const endpoint=safeUrl(config.snapshot_url),pricing=safeUrl(config.pricing_url);
 if(endpoint.origin!==base.origin)throw Error('采集接口须与来源地址同域');
 if(/(^|\.)priceai\.cc$/i.test(endpoint.hostname))throw Error('采集来源须为商家原站');
 if(config.monitor_url){const monitor=safeUrl(config.monitor_url);if(/(^|\.)priceai\.cc$/i.test(monitor.hostname))throw Error('监测来源须为商家原站');if(!['performance','zivv','channel_v2'].includes(config.monitor_kind))throw Error('请选择监测接口类型');}
 if(config.availability_unit&&!['fraction','percent'].includes(config.availability_unit))throw Error('可用率单位无效');
 if(config.request_timeout_seconds!==undefined&&(!Number.isInteger(config.request_timeout_seconds)||config.request_timeout_seconds<10||config.request_timeout_seconds>60))throw Error('读取超时须为 10–60 秒');
 return {name:b.name.trim(),base_url:base.href,collector:b.collector,interval_minutes:interval,enabled:b.enabled!==false,adaptive_enabled:b.adaptive_enabled!==false,
 config:{snapshot_url:endpoint.href,pricing_url:pricing.href,...(config.website_url?{website_url:safeUrl(config.website_url).href}:{}),...(config.monitor_url?{monitor_url:safeUrl(config.monitor_url).href,monitor_kind:config.monitor_kind}:{}),...(config.availability_unit?{availability_unit:config.availability_unit}:{}),...(config.request_timeout_seconds?{request_timeout_seconds:config.request_timeout_seconds}:{})}};
}
