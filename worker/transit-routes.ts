import type { SupabaseClient } from '@supabase/supabase-js';
import type { Env } from './types';
import { validateTransitSource } from './transit';
import { cachedPublic, publicCacheKey } from './public-cache';
const json=(body:unknown,status=200)=>Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
const checked=<T extends {error:any}>(r:T):T=>{if(r.error)throw Error(r.error.message);return r;};
async function body(req:Request){const text=await req.text();if(text.length>16000)throw Error('请求过大');return JSON.parse(text);}
async function invoke(env:Env,payload:unknown) {
 const url=new URL('/functions/v1/collect-transit',env.SUPABASE_URL);
 const response=await fetch(url,{method:'POST',headers:{Authorization:`Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,'X-Crawler-Token':env.CRAWLER_TOKEN??'','Content-Type':'application/json'},body:JSON.stringify(payload),signal:AbortSignal.timeout(130000)});
 if(!response.ok)throw Error(`采集服务 HTTP ${response.status}`);
 return response.json();
}
export async function publicTransit(req:Request,env:Env,ctx?:ExecutionContext) {
 const url=new URL(req.url),offset=Number(url.searchParams.get('offset')??0),limit=Number(url.searchParams.get('limit')??2);
 if(!Number.isSafeInteger(offset)||offset<0||offset>10000||!Number.isInteger(limit)||limit<1||limit>2)return json({error:'分页参数无效'},400);
 // Strip unrelated query parameters from cache keys. Serve only public snapshot fields.
 const key=publicCacheKey(url,{limit,offset});
 return cachedPublic(key,ctx,async()=>{
 const upstream=await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/transit_page`,{method:'POST',headers:{apikey:env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,'Content-Type':'application/json'},body:JSON.stringify({p_limit:limit,p_offset:offset}),signal:AbortSignal.timeout(20000)});
 if(!upstream.ok){await upstream.body?.cancel();return json({error:'API 报价暂时无法读取，请稍后重试'},502);}
 const response=new Response(upstream.body,{headers:{'Content-Type':'application/json;charset=utf-8','Cache-Control':'public,max-age=60,s-maxage=300','X-Content-Type-Options':'nosniff'}});
 return response;
 });
}
// This router is called only after the existing ADMIN_TOKEN authentication gate.
export async function adminTransit(req:Request,env:Env,client:SupabaseClient) {
 const path=new URL(req.url).pathname.replace('/api/admin/transit','');
 if(path==='/sources'&&req.method==='GET')return json({sources:checked(await client.from('transit_sources').select('*').order('created_at')).data});
 if(path==='/runs'&&req.method==='GET')return json({runs:checked(await client.from('transit_crawl_runs').select('*,sources:transit_sources(name)').order('started_at',{ascending:false}).limit(50)).data});
 const match=path.match(/^\/sources\/([a-z0-9-]{1,100})$/);
 if((path==='/sources'||path==='/preview')&&req.method==='POST') {
  let row;try{row=validateTransitSource(await body(req));}catch(e){return json({error:(e as Error).message},400);}
  if(path==='/preview')return json(await invoke(env,{preview:row}));
  return json({source:checked(await client.from('transit_sources').insert(row).select().single()).data},201);
 }
 if(match&&req.method==='PATCH') {
  const existing=checked(await client.from('transit_sources').select('*').eq('id',match[1]).maybeSingle()).data;
  if(!existing)return json({error:'来源不存在'},404);
  let row;try{const b=await body(req);row=validateTransitSource({...existing,...Object.fromEntries(['name','base_url','config','collector','interval_minutes','enabled'].filter(k=>Object.hasOwn(b,k)).map(k=>[k,b[k]]))});}catch(e){return json({error:(e as Error).message},400);}
  // Invalidate old in-flight work when configuration changes, and make re-enabled sources due.
  return json({source:checked(await client.from('transit_sources').update({...row,lease_token:null,lease_until:null,next_crawl_at:new Date().toISOString()}).eq('id',match[1]).select().single()).data});
 }
 if(path==='/crawl'&&req.method==='POST') {
  let b;try{b=await body(req);}catch{return json({error:'请求格式无效'},400);}
  if(b.source_id!=null&&(typeof b.source_id!=='string'||!/^[a-z0-9-]{1,100}$/.test(b.source_id)))return json({error:'无效来源'},400);
  return json(await invoke(env,{source_id:b.source_id}));
 }
 return json({error:'Not found'},404);
}
