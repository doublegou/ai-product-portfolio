/** Replay an archived public snapshot through unchanged production loaders and rules. No network. */
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {gzipSync,gunzipSync} from 'node:zlib';
import assert from 'node:assert/strict';
import {loadOffers} from '../src/pricemapai-web-production/src/data/client.ts';
import {loadTransit} from '../src/pricemapai-web-production/src/data/transit-client.ts';
import {isFresh,isAvailable,lowestIds} from '../src/pricemapai-web-production/src/lib/offers.ts';
import {catalogEntries} from '../src/pricemapai-web-production/src/lib/catalog.ts';
import {combinedRate,stationMonitoring} from '../src/pricemapai-web-production/src/lib/apiTransit.ts';
const here=path.dirname(fileURLToPath(import.meta.url));
const base=path.join(here,'fixtures/public-snapshot-20261017');
const capture=JSON.parse(fs.readFileSync(path.join(base,'capture.json'),'utf8'));
const manifest=JSON.parse(fs.readFileSync(path.join(base,'latest.json'),'utf8'));
const now=Date.parse(capture.captured_at),sha=(v:Buffer)=>createHash('sha256').update(v).digest('hex');
assert.equal(sha(fs.readFileSync(path.join(base,'latest.json'))),capture.manifest_sha256);
for(const file of capture.pages)assert.equal(sha(fs.readFileSync(path.join(base,file.local_file))),file.sha256);
let requests:string[]=[];
const fetcher:typeof fetch=async (input:any)=>{
 const url=String(input);requests.push(url);
 const known=url==='/data/latest.json'?'latest.json':capture.pages.find((p:any)=>p.path===url)?.local_file;
 if(!known)throw Error('Non-fixture request rejected: '+url);
 return new Response(fs.readFileSync(path.join(base,known)));
};
const originalNow=Date.now;
try{
 Date.now=()=>now;
 const offers=await loadOffers(fetcher),stations=await loadTransit(fetcher);
 const fresh=offers.filter(o=>isFresh(o,now)),available=offers.filter(o=>isAvailable(o,now));
 const eligible=available.filter(o=>o.comparison_key&&!o.review_required);
 const groups=new Map<string,typeof eligible>();
 for(const o of eligible){const key=JSON.stringify([o.comparison_key,o.currency,o.delivery,o.duration_days]);groups.set(key,[...(groups.get(key)??[]),o]);}
 const multi=[...groups.values()].filter(g=>new Set(g.map(o=>o.sources.base_url)).size>=2);
 const entries=catalogEntries(offers,now),starting=entries.filter(e=>e.priceKind==='lowest');
 const prices=stations.flatMap(s=>s.prices),freshStations=stations.filter(s=>Date.parse(s.expiresAt!)>now);
 const counter=(rows:any[],key:string)=>Object.fromEntries([...new Set(rows.map(x=>String(x[key])))].sort().map(k=>[k,rows.filter(x=>String(x[key])===k).length]));
 const faultCases=[];
 for(const kind of ['missing_page','mixed_version','duplicate_offer']){
  let attempt=0;
  const badFetch:typeof fetch=async(input:any)=>{
   const url=String(input);
   if(url!==manifest.offers.pages[0])return fetcher(input);
   attempt++;
   if(kind==='missing_page')return new Response('Not found',{status:404});
   const body=JSON.parse(gunzipSync(fs.readFileSync(path.join(base,'offers-0.json.gz'))).toString());
   if(kind==='mixed_version')body.version='000000000000000000000000';
   else body.offers[1]=body.offers[0];
   return new Response(gzipSync(JSON.stringify(body)));
  };
  let rejected=false,error='';
  try{await loadOffers(badFetch);}catch(e){rejected=true;error=String(e);}
  assert.equal(rejected,true);
  faultCases.push({case:kind,rejected,page_requests:attempt,error});
 }
 const result={
  scope:'Archived public snapshot replay, not merchant truth verification, an independent model benchmark, or user conversion measurement.',
  source_commit:'3c97c452105bce6626ec2c81ef7c940829ddc7a5',
  captured_at:capture.captured_at,snapshot_generated_at:manifest.generated_at,version:manifest.version,
  snapshot_age_at_capture_minutes:(now-Date.parse(manifest.generated_at))/60000,
  integrity:{pages:capture.pages.length,manifest_and_page_hashes_verified:true,production_loaders_accept_all_rows:true,offer_ids_unique:new Set(offers.map(o=>o.id)).size===offers.length,station_ids_unique:new Set(stations.map(s=>s.id)).size===stations.length},
  subscription:{total:offers.length,merchant_identities:new Set(offers.map(o=>o.sources.base_url)).size,fresh:fresh.length,fresh_in_stock:available.length,stock_distribution:counter(offers,'stock_status'),review_required:offers.filter(o=>o.review_required).length,strict_eligible_quotes:eligible.length,strict_groups_with_multiple_merchants:multi.length,strict_lowest_badges:lowestIds(offers,now).size,
   catalog_categories:entries.length,categories_with_quotes:entries.filter(e=>e.offers.length).length,categories_showing_lowest_label:starting.length,category_lowest_selected_review_required:starting.filter(e=>e.priceOffer?.review_required).length,
   note:'Catalog lowest label means the lowest fresh in-stock CNY quote in a broad category, without requiring comparison_key. Detail lowestIds is stricter. Counts therefore differ.'},
  api:{stations:stations.length,fresh_stations:freshStations.length,quotes:prices.length,currency_distribution:counter(prices,'currency'),billing_distribution:counter(prices,'billingMode'),quotes_eligible_for_combined_rate:prices.filter(p=>combinedRate(p)!=null).length,stations_with_current_disclosed_rate:stations.filter(s=>stationMonitoring(s)?.rate!=null).length,monitoring_note:'Merchant-disclosed telemetry; neither independent availability nor model identity verification.'},
  payload:{gzip_bytes:capture.pages.reduce((n:number,p:any)=>n+p.bytes,0),uncompressed_bytes:capture.pages.reduce((n:number,p:any)=>n+p.uncompressed_bytes,0)},
  fault_injection:faultCases,
  plus_60_minutes:{scenario:'Simulated passage of 60 minutes without any new snapshot; not a later production observation.',fresh_offers:offers.filter(o=>isFresh(o,now+3600000)).length,fresh_in_stock:offers.filter(o=>isAvailable(o,now+3600000)).length},
  passed:true
 };
 fs.writeFileSync(path.join(here,'snapshot-replay.json'),JSON.stringify(result,null,2)+'\n');
 console.log(JSON.stringify(result,null,2));
}finally{Date.now=originalNow;}
