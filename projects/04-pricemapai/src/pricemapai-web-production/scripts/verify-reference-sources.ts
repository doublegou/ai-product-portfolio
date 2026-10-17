import {readFileSync,writeFileSync} from 'node:fs';
import {collect} from '../worker/collectors';
import {safeUrl,download,readLimited,assertRobots} from '../worker/network';
import type {Source} from '../worker/types';
const comparison=JSON.parse(readFileSync('artifacts/merchant-comparison.json','utf8'));
const pending=[...comparison.missing];
const results:any[]=[];
const existing=JSON.parse(readFileSync('config/verified-sources.json','utf8'));
const known=new Set(existing.map((s:any)=>s.base_url.replace(/\/$/,'')));
const save=()=>writeFileSync('artifacts/source-verification.json',JSON.stringify({checked_at:new Date().toISOString(),results},null,2));
await Promise.all(Array.from({length:4},async()=>{while(pending.length){const row=pending.shift();const result:any={reference:row,status:'pending'};try{
 let u=safeUrl(row.url);let source:any={name:row.name,base_url:u.href.replace(/\/$/,''),config:{},interval_minutes:15};
 if(row.collector==='16688_shop_api'){
   await assertRobots(u.href,['/shopApi/shop/detail']);
   const shop=u.pathname.split('/')[2];
   const d=JSON.parse(await readLimited(await download(new URL('/shopApi/shop/detail',u).href,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({shop_no:shop})},u.origin)));
   const detail=d.data?.shop??d.data;
   if(d.code!==1||!/^S\d+$/.test(String(detail?.shop_no))) throw new Error('原站无法确认店铺身份');
   source={...source,name:detail.name||row.name,base_url:`https://www.16688.com.cn/shop/${detail.shop_no}`,collector:'16688'};
 }else if(row.collector==='shopApi'||u.hostname==='pay.ldxp.cn'){
   if(u.hostname==='pay.ldxp.cn'){
    const response=await fetch(u,{redirect:'manual',signal:AbortSignal.timeout(15000)});
    const location=response.headers.get('location');
    if(![301,302,307,308].includes(response.status)||!location)throw new Error('旧域名未返回可验证的跳转');
    const target=safeUrl(location,u.href);if(target.hostname!=='wzyp.cn'||target.pathname!==u.pathname)throw new Error('旧域名跳转需要人工核验');u=target;
   }
   const token=u.pathname.match(/^\/shop\/([^/]+)\/?$/)?.[1];if(!token)throw new Error('无法识别店铺编号');
   await assertRobots(u.href,['/shopApi/Shop/info']);
   const d=JSON.parse(await readLimited(await download(new URL('/shopApi/Shop/info',u).href,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token})},u.origin)));
   if(d.code!==1||!d.data?.token)throw new Error('原站店铺不可用');
   source={...source,name:d.data.nickname||row.name,base_url:`${u.origin}/shop/${d.data.token}`,collector:'shopapi',config:{shop_token:d.data.token}};
 }else if(row.collector==='dujiao'){source.collector='dujiao';source.base_url=u.origin;}
 else if(row.collector==='kami'){source.collector='kami';source.base_url=u.origin;}
 else { result.status='needs_adapter'; await assertRobots(u.href,[u.pathname]); const response=await download(u.href,{},u.origin);const html=await readLimited(response);result.detail=`原站 HTTP ${response.status}，需核验独立页面结构`;result.title=html.match(/<title[^>]*>([^<]*)/i)?.[1];results.push(result);save();continue; }
 result.source=source;
 if(known.has(source.base_url)){result.status='alias_existing';result.detail='原站证实与已接入地址指向同一店铺';}
 else {const snapshot=await collect(source as Source);result.status='verified';result.offer_count=snapshot.offers.length;result.complete=snapshot.complete;known.add(source.base_url);}
 }catch(e){result.status='failed';result.detail=e instanceof Error?e.message:String(e);}
 results.push(result);save();if(results.length%25===0)console.log(JSON.stringify({done:results.length,total:comparison.missing.length,verified:results.filter(r=>r.status==='verified').length,failed:results.filter(r=>r.status==='failed').length}));await new Promise(r=>setTimeout(r,250));}}));
save();console.log(JSON.stringify({done:results.length,counts:results.reduce((a,r)=>({...a,[r.status]:(a[r.status]||0)+1}),{})}));
