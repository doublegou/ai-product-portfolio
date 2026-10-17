import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeTransit,normalizeZivv,normalizeOnehop,normalizePublicModels,normalizeNewApi,collectTransit,validateTransitSource,type TransitSource} from '../worker/transit';
import {rollupMonitoring,performanceSummary,channelMonitorV2} from '../worker/transit-monitoring';
import type {PublicMonitoring} from '../src/lib/apiTransit';
const at=new Date().toISOString();
const source:TransitSource={id:'test-com',name:'Test',base_url:'https://example.com/',collector:'transit',enabled:true,interval_minutes:15,config:{snapshot_url:'https://example.com/api/public/transit/v1/snapshot',pricing_url:'https://example.com/public/transit'}};
const monitor=(rate:number,samples:number|null):PublicMonitoring=>({rate,samples,latencyMs:100,latencyLabel:'探测延迟',scope:'分组 · 7 天',sourceUrl:source.base_url,updatedAt:at,history:[]});
test('station aggregation weights real independent samples and discloses unweighted missing counts',()=>{
 let m=rollupMonitoring([monitor(1,90),monitor(0,10)],'汇总',source.base_url)!;assert.equal(m.rate,.9);assert.equal(m.samples,100);assert.match(m.aggregation!,/加权/);
 m=rollupMonitoring([monitor(1,null),monitor(0,10)],'汇总',source.base_url)!;assert.equal(m.rate,.5);assert.equal(m.samples,null);assert.match(m.aggregation!,/等权/);
 assert.equal(rollupMonitoring([{...monitor(1,100),updatedAt:'2020-01-01'},monitor(0,1)],'汇总',source.base_url)!.rate,0);
});
test('multiple model/spec prices do not multiply a group in the outer station average',()=>{
 const data:any={schema_version:'ai-transit.v1',groups:[{name:'A',models:['gpt-a','gpt-b','gpt-c'].map(standard_model=>({standard_model}))},{name:'B',models:[{standard_model:'gpt-d'}]}],monitoring:[{name:'A',primary_model:'gpt-a',availability_7d:100,last_checked_at:at},{name:'B',primary_model:'gpt-d',availability_7d:0,last_checked_at:at}]};
 const result=normalizeTransit(data,source);assert.equal(result.prices.length,4);assert.equal(result.publicMonitoring!.rate,.5);assert.equal(result.publicMonitoring!.tokensPerSecond,null);
 const before=JSON.stringify(data);normalizeTransit(data,{...source,config:{...source.config,availability_unit:'fraction'}});assert.equal(JSON.stringify(data),before);
 const noSamples={...data,monitoring:[{name:'A',availability_7d:0},{name:'B',availability_7d:0}]};
 assert.equal(normalizeTransit(noSamples,source).publicMonitoring,undefined);
});
test('performance data keeps generation speed separate from total token throughput and has no invented sample count',()=>{
 const p=performanceSummary({success:true,data:{window_end:Date.now()/1000,summary:{success_rate:90,avg_tps:42,avg_latency_ms:35000},models:[{model_name:'gpt-a',success_rate:50,avg_tps:20,recent_success_series:[{ts:Date.now()/1000,success_rate:50}]}]}},source.base_url,at);
 assert.equal(p.station!.rate,.9);assert.equal(p.station!.tokensPerSecond,42);assert.equal(p.station!.throughputLabel,'平均生成速度');assert.equal(p.station!.samples,null);assert.equal(p.models.get('gpt-a')!.history[0].samples,null);
});
test('Zivv prices already include group factor and media variants remain independent',()=>{
 const s=normalizeZivv({data:[{id:'gpt-a',groups:[{name:'Group',multiplier:3,input_rate:2,output_rate:6}]},{id:'gpt-image-2',groups:[{name:'Image',image_rate_1k:.1,image_rate_2k:.2}]}]},source);
 assert.equal(s.prices[0].inputPrice,2);assert.equal(s.prices[0].currency,'USD_CREDIT');assert.equal(s.prices.length,3);assert.deepEqual(s.prices.slice(1).map(p=>p.fixedPrice),[.1,.2]);
});
test('OneHop rejects incomplete catalogs and retains distinct tiered prices and unknown uptime samples',()=>{
 const row={fullSlug:'openai/gpt-a',upstreamModelId:'gpt-a',inputPricePer1m:'1.5',outputPricePer1m:'6',displayMetrics:{successRate:.9,uptime24h:[{hour:at,rate:.9}]}};
 assert.throws(()=>normalizeOnehop({data:{items:[row],nextCursor:'next'}},source),/不完整/);
 const s=normalizeOnehop({data:{items:[row,{...row,fullSlug:'openai/gpt-tier',tokenPricingBands:[{},{range:200000}]}]}},source);
 assert.equal(s.prices[0].inputPrice,1.5);assert.equal(s.prices[1].inputPrice,null);assert.equal(s.prices[1].billingMode,'tiered');assert.equal(s.publicMonitoring!.samples,null);
});
test('standalone public model catalogs do not invent group prices, and V2 monitors preserve hidden throughput',()=>{
 const s=normalizePublicModels({data:{models:[{name:'gpt-a',pricing:{billing_mode:'token',input_price:.000002,output_price:.000004}}]}},source);
 assert.equal(s.prices[0].inputPrice,2);assert.equal(s.prices[0].comparisonEligible,false);assert.equal(s.prices[0].priceBasis,'catalog_base');
 const m=channelMonitorV2({metrics:{success_rate:1,ttft:{avg_ms:2000}},health:{overall:'healthy'}},source.base_url,at,'全站')!;assert.equal(m.rate,1);assert.equal(m.tokensPerSecond,null);assert.equal(m.samples,null);
});
test('New API per-group tier expressions never inherit a misleading flat model price',()=>{
 const s=normalizeNewApi({success:true,data:[{model_name:'gpt-a',enable_groups:['A','B'],quota_type:0,model_ratio:2,completion_ratio:3,group_billing:{A:{billing_mode:'tiered_expr',billing_expr:'dynamic'}}}],group_ratio:{A:1,B:1}},source);
 assert.equal(s.prices[0].inputPrice,null);assert.equal(s.prices[1].inputPrice,4);
});
test('public feed adapter uses anonymous original endpoints; monitor failure cannot erase valid prices',async()=>{
 const original=globalThis.fetch,urls:string[]=[];
 globalThis.fetch=(async(input:any,init:any)=>{urls.push(String(input));assert.equal(new Headers(init.headers).has('Authorization'),false);return String(input).includes('perf-metrics')?new Response('',{status:404}):Response.json({schema_version:'ai-transit.v1',groups:[{name:'A',models:[{standard_model:'gpt-a'}]}]});}) as typeof fetch;
 try{const s=await collectTransit({...source,config:{...source.config,monitor_url:'https://example.com/api/perf-metrics/summary?period=24',monitor_kind:'performance'}});assert.equal(s.prices.length,1);assert.match(s.monitoringError!,/404/);assert.equal(urls.some(u=>u.includes('/robots.txt')),false);}finally{globalThis.fetch=original;}
 assert.throws(()=>validateTransitSource({...source,config:{...source.config,monitor_url:'https://127.0.0.1/api/status',monitor_kind:'zivv'}}));
 assert.throws(()=>validateTransitSource({...source,config:{...source.config,monitor_url:'https://priceai.cc/api/status',monitor_kind:'zivv'}}));
 assert.equal(validateTransitSource({...source,config:{...source.config,request_timeout_seconds:55}}).config.request_timeout_seconds,55);
 for(const value of [0,9,61,Infinity])assert.throws(()=>validateTransitSource({...source,config:{...source.config,request_timeout_seconds:value}}),/超时/);
});
