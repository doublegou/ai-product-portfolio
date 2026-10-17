import test from 'node:test';
import assert from 'node:assert/strict';
import {billingConversion,normalizeTransit,normalizeNewApi,validateTransitSource,type TransitSource} from '../worker/transit';
import {isTieredPrice,combinedRate,priceMetric,bestPrice,quoteMonitoring} from '../src/lib/apiTransit';
import {loadTransit} from '../src/data/transit-client';
import worker from '../worker/index';
import type {Env} from '../worker/types';
const source:TransitSource={id:'example-com',name:'Example',base_url:'https://example.com/',collector:'transit',enabled:true,interval_minutes:15,config:{snapshot_url:'https://example.com/api/public/transit/v1/snapshot',pricing_url:'https://example.com/public/transit'}};
const snapshot=()=>({schema_version:'ai-transit.v1',generated_at:new Date().toISOString(),billing:{currency:'CNY',credit_currency:'USD',recharge_ratio:'1 CNY = 2 USD balance'},groups:[{name:'standard',rate_multiplier:3,models:[{standard_model:'gpt-test',billing_mode:'token',price:{input_usd_per_token:.000002,output_usd_per_token:.000008}}]}]});
test('prices apply group and recharge factors exactly once, without assuming a foreign exchange rate',()=>{
 const s=snapshot();const p=normalizeTransit(s,source).prices[0];assert.equal(p.inputPrice,3);assert.equal(p.outputPrice,12);assert.equal(combinedRate(p),1.5);assert.equal(quoteMonitoring(p),undefined);
 const applied=normalizeTransit({...s,billing:{...s.billing,group_multiplier_applied:true}},source).prices[0];assert.equal(applied.inputPrice,1);assert.equal(combinedRate(applied),null);
 const usd=normalizeTransit({...s,billing:{currency:'USD',credit_currency:'USD',recharge_ratio:'1 USD = 7 USD'}},source).prices[0];assert.equal(usd.currency,'USD');assert.equal(combinedRate(usd),null);
 assert.equal(billingConversion({currency:'USD',credit_currency:'CNY',recharge_ratio:'1 CNY = 1 USD credit'}).currency,'USD_CREDIT');
 assert.equal(billingConversion({currency:'CNY',credit_currency:'USD',recharge_ratio:'1 USD balance per 1 CNY'}).factor,1);
});
test('unknown and tiered prices are not silently converted to zero or a starting price',()=>{
 const s=snapshot();s.groups[0].models[0].price.input_usd_per_token=null as any;
 let p=normalizeTransit(s,source).prices[0];assert.equal(p.inputPrice,null);
 (s.groups[0].models[0] as any).intervals=[{min:0},{min:200000}];p=normalizeTransit(s,source).prices[0];assert.equal(p.outputPrice,null);assert.equal(combinedRate(p),null);assert.match(p.note!,/阶梯/);assert.equal(p.billingMode,'tiered');assert.equal(isTieredPrice(p),true);assert.equal(isTieredPrice({...p,billingMode:'token'}),true);
 assert.throws(()=>normalizeTransit({...s,groups:[]},source),/为空/);
});
test('monitoring attaches to the correct group/model, preserves zero and unknown sample counts',()=>{
 const s:any=snapshot();s.monitoring=[{group_name:'other',primary_model:'gpt-test',availability_7d:100}];assert.equal(normalizeTransit(s,source).prices[0].publicMonitoring,undefined);
 s.monitoring=[{group_name:'standard',primary_model:'gpt-test',availability_7d:0,last_checked_at:new Date().toISOString()}];let p=normalizeTransit(s,source).prices[0];assert.equal(p.publicMonitoring?.rate,0);assert.equal(p.publicMonitoring?.samples,null);
 s.monitoring[0].sample_count_7d=0;p=normalizeTransit(s,source).prices[0];assert.equal(p.publicMonitoring?.rate,null);
 s.monitoring[0]={group_name:'standard',primary_model:'other-model',availability_7d:99};p=normalizeTransit(s,source).prices[0];assert.match(p.publicMonitoring!.scope,/分组探测（other-model）/);
});
test('New API conversion uses quota units, group ratio and output ratio, with no invented cash conversion',()=>{
 const s=normalizeNewApi({success:true,group_ratio:{default:2},data:[{model_name:'gpt-test',quota_type:0,model_ratio:1.25,completion_ratio:4,enable_groups:['default']},{model_name:'image-test',quota_type:1,model_price:.1,enable_groups:['default']},{model_name:'gpt-tier',quota_type:0,model_ratio:2,billing_expr:'arbitrary expression',enable_groups:['default']}]},source);
 assert.equal(s.prices[0].inputPrice,5);assert.equal(s.prices[0].outputPrice,20);assert.equal(s.prices[0].currency,'USD_CREDIT');assert.equal(combinedRate(s.prices[0]),null);assert.match(priceMetric(s.prices[1]),/额度 \$0.2\/次/);assert.equal(s.prices[2].inputPrice,null);
});
test('expired prices do not rank as current lowest prices or current monitoring',()=>{
 const p=normalizeTransit(snapshot(),source).prices[0];p.expiresAt='2020-01-01T00:00:00Z';p.publicMonitoring={rate:1,samples:2,latencyMs:10,latencyLabel:'延迟',scope:'模型',sourceUrl:source.base_url,updatedAt:new Date().toISOString(),history:[]};assert.equal(bestPrice([p]),undefined);assert.equal(quoteMonitoring(p)?.rate,null);
});
test('source configuration rejects private URLs, cross-origin endpoints, bad intervals and reference-site collection',()=>{
 assert.throws(()=>validateTransitSource({...source,base_url:'http://localhost/'}));
 assert.throws(()=>validateTransitSource({...source,config:{...source.config,snapshot_url:'https://other.com/api'}}),/同域/);
 assert.throws(()=>validateTransitSource({...source,interval_minutes:1}));
 assert.throws(()=>validateTransitSource({...source,base_url:'https://priceai.cc',config:{...source.config,snapshot_url:'https://priceai.cc/api'}}),/原站/);
});
const page=(id:string)=>({source_id:id,data:{...normalizeTransit(snapshot(),{...source,id})},last_seen_at:new Date().toISOString(),expires_at:new Date(Date.now()+2700000).toISOString()});
test('all API relay admin routes are protected by the existing admin gate',async()=>{
 const env={SUPABASE_URL:'https://example.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test',ADMIN_TOKEN:'test'} as Env;
 for(const path of ['sources','runs','preview','crawl','sources/example-com']){const response=await worker.fetch(new Request(`https://example.com/api/admin/transit/${path}`,{method:path==='sources'||path==='runs'?'GET':'POST'}),env);assert.equal(response.status,401);}
 const r=await worker.fetch(new Request('https://example.com/api/transit?limit=100'),env);assert.equal(r.status,410);
});
