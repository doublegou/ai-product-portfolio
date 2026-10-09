import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSnapshot } from '../snapshot/build';
import { publishAssets } from '../snapshot/publish';
import { loadOffers } from '../src/data/client';
import { loadTransit } from '../src/data/transit-client';
const offer={id:'a',raw_title:'ChatGPT Plus',platform:'ChatGPT',plan:'Plus',delivery:'代充',duration_days:30,comparison_key:'plus-30',review_required:false,price:120,currency:'CNY',stock_status:'in_stock',purchase_url:'https://shop.example.com/1',last_seen_at:'2026-10-09T00:00:00Z',expires_at:'2026-10-10T00:00:00Z',sources:{name:'店铺',base_url:'https://shop.example.com'}};
const station={source_id:'relay',data:{id:'relay',name:'中转站',prices:[{inputPrice:1}]},last_seen_at:offer.last_seen_at,expires_at:offer.expires_at};
const input={generated_at:'2026-10-09T00:00:00Z',offers:[offer],transit:[station]};
test('both clients read only static files and assign collection freshness',async()=>{
 const {files}=await buildSnapshot(input);const paths:string[]=[];
 const fetcher=(async(url:string)=>{paths.push(url);assert.ok(url.startsWith('/data/'));return new Response(files[url]);})as typeof fetch;
 assert.equal((await loadOffers(fetcher))[0].id,'a');
 const stations=await loadTransit(fetcher);assert.equal(stations[0].prices[0].lastVerifiedAt,station.last_seen_at);
 assert.ok(paths.every(path=>!path.includes('/api/')));
});
test('incomplete pages and mixed versions never produce a published dataset',async()=>{
 const {files}=await buildSnapshot(input);
 for(const breakPage of [(body:any)=>({...body,offers:[]}),(body:any)=>({...body,version:'bad'})]){
 const fetcher=(async(url:string)=>{if(url==='/data/latest.json')return new Response(files[url]);
 const body=await new Response(new Blob([files[url]]).stream().pipeThrough(new DecompressionStream('gzip'))).json();
 const changed=breakPage(body);return new Response(new Blob([JSON.stringify(changed)]).stream().pipeThrough(new CompressionStream('gzip')));})as typeof fetch;
 await assert.rejects(()=>loadOffers(fetcher),/完整|版本/);
 }
});
test('a stale manifest retries once with fresh static files, without database fallback',async()=>{
 const old=await buildSnapshot(input),fresh=await buildSnapshot({...input,generated_at:'2026-10-09T00:05:00Z'});let manifests=0;
 const fetcher=(async(url:string)=>url==='/data/latest.json'?Response.json(++manifests===1?old.manifest:fresh.manifest):fresh.files[url]?new Response(fresh.files[url]):new Response('missing',{status:404}))as typeof fetch;
 assert.equal((await loadOffers(fetcher)).length,1);assert.equal(manifests,2);
});
test('empty snapshots remain empty, invalid rows and unsafe manifest paths are rejected',async()=>{
 const {files}=await buildSnapshot({...input,offers:[],transit:[]});
 const fetcher=(async(url:string)=>new Response(files[url]))as typeof fetch;
 assert.deepEqual(await loadOffers(fetcher),[]);assert.deepEqual(await loadTransit(fetcher),[]);
 await assert.rejects(()=>buildSnapshot({...input,offers:[{...offer,price:null}]}),/格式/);
 const bad=(async()=>Response.json({...JSON.parse(new TextDecoder().decode(files['/data/latest.json'])),offers:{count:1,pages:['https://evil.example/']}}))as typeof fetch;
 await assert.rejects(()=>loadOffers(bad),/分页/);
});
test('failed asset upload never switches the live deployment',async()=>{
 const {files}=await buildSnapshot(input);let deployed=false;
 const fetcher=(async(url:string,init:RequestInit)=>{
 if(init.method==='PUT'){deployed=true;return Response.json({success:true,result:{}});}
 if(url.endsWith('assets-upload-session')){const m=JSON.parse(init.body as string).manifest;return Response.json({success:true,result:{jwt:'session',buckets:[Object.values(m).map((v:any)=>v.hash)]}});}
 return Response.json({success:false,errors:[{code:1000}]},{status:500});
 })as typeof fetch;
 await assert.rejects(()=>publishAssets(files,'test',fetcher),/publishing failed/);assert.equal(deployed,false);
});
test('a complete asset set is activated with static cache headers and no database bindings',async()=>{
 const {files}=await buildSnapshot(input);let metadata:any;
 const fetcher=(async(url:string,init:RequestInit)=>{
 if(init.method==='PUT'){metadata=JSON.parse((init.body as FormData).get('metadata') as string);return Response.json({success:true,result:{}});}
 return Response.json({success:true,result:{jwt:'complete',buckets:[]}});
 })as typeof fetch;
 await publishAssets(files,'test',fetcher);assert.equal(metadata.main_module,undefined);assert.equal(metadata.bindings,undefined);assert.match(metadata.assets.config._headers,/max-age=60/);
});

test('snapshot files exclude unexpected private fields at every published level',async()=>{
 const secret='private-collector-token';
 const {files}=await buildSnapshot({...input,offers:[{...offer,config:{token:secret},sources:{...offer.sources,api_key:secret}}],transit:[{...station,lease_token:secret,data:{...station.data,config:{token:secret},prices:[{inputPrice:1,api_key:secret,publicMonitoring:{rate:1,token:secret,history:[{at:input.generated_at,token:secret}]}}]}}]});
 for(const [path,content] of Object.entries(files)){const text=path.endsWith('.gz')?await new Response(new Blob([content]).stream().pipeThrough(new DecompressionStream('gzip'))).text():new TextDecoder().decode(content);assert.ok(!text.includes(secret));}
});
