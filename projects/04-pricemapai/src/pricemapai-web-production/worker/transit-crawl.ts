import { createClient } from '@supabase/supabase-js';
import { collectTransit, type TransitSource } from './transit.ts';
import type { Env } from './types.ts';
const checked = <T extends {error: any}>(r:T):T => {if(r.error)throw Error(r.error.message);return r;};
export async function crawlTransit(env:Pick<Env,'SUPABASE_URL'|'SUPABASE_SERVICE_ROLE_KEY'>,id?:string) {
 const client=createClient(env.SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
 const sources=checked(await client.rpc('claim_transit_sources',{batch_size:id?1:4,requested_id:id??null})).data as TransitSource[];
 const results:{source:string;status:string;count?:number;error?:string}[]=[];
 const queue=[...(sources??[])];
 await Promise.all(Array.from({length:2},async()=>{while(queue.length){
  const source=queue.shift()!;
  const run=checked(await client.from('transit_crawl_runs').insert({source_id:source.id}).select('id').single()).data!;
  const args={p_source_id:source.id,p_lease_token:source.lease_token,p_run_id:run.id};
  try {
   const snapshot=await collectTransit(source);
   checked(await client.rpc('complete_transit_crawl',{...args,p_snapshot:snapshot}));
   results.push({source:source.name,status:'success',count:snapshot.prices.length});
  } catch(e) {
   const error=e instanceof Error?e.message:'原站采集失败';
   checked(await client.rpc('complete_transit_crawl',{...args,p_error:error}));
   results.push({source:source.name,status:'failed',error});
  }
 }}));
 return results;
}
