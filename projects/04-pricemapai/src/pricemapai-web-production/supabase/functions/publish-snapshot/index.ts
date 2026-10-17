import { timingSafeEqual } from 'node:crypto';
import { buildSnapshot } from '../../../snapshot/build.ts';
import { publishAssets, retainCurrentSnapshot } from '../../../snapshot/publish.ts';
Deno.serve(async(request:Request)=>{
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'',token=Deno.env.get('CRAWLER_TOKEN')??'';
 const expected=new TextEncoder().encode(token),actual=new TextEncoder().encode(request.headers.get('X-Crawler-Token')??'');
 if(!key||!token||expected.length!==actual.length||!timingSafeEqual(expected,actual))return Response.json({error:'Unauthorized'},{status:401});
 if(request.method!=='POST')return new Response(null,{status:405});
 const publishToken=Deno.env.get('CLOUDFLARE_SNAPSHOT_API_TOKEN'),syncUrl=Deno.env.get('SNAPSHOT_SYNC_URL');
 if(!publishToken&&!syncUrl)return Response.json({error:'Publisher credential not configured'},{status:503});
 async function rpc(name:string,body:unknown={}) {
  const r=await fetch(`${Deno.env.get('SUPABASE_URL')}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(45000)});
  if(!r.ok)throw Error(`Snapshot database operation failed: ${name}, HTTP ${r.status}`);
  if(r.status===204)return null;
  const text=await r.text();return text?JSON.parse(text):null;
 }
 let lease:string|null=null;
 try {
  lease=await rpc('claim_snapshot_publication');
  if(!lease)return Response.json({skipped:'publication already running'});
  if(syncUrl){
   let syncBytes=0;
   const send=async(batch:unknown)=>{
    const body=JSON.stringify(batch);
    syncBytes=new TextEncoder().encode(body).byteLength;
    return fetch(new URL('/sync',syncUrl),{method:'POST',headers:{'Content-Type':'application/json','X-Crawler-Token':token},body,signal:AbortSignal.timeout(110000)});
   };
   async function budgetPause(batch:any){
    // Keep analytics scheduling current even while quote-byte exports pause.
    const status=await fetch(new URL('/status',syncUrl),{method:'POST',headers:{'X-Crawler-Token':token},signal:AbortSignal.timeout(15000)});
    if(!status.ok)throw Error(`Heat status failed: HTTP ${status.status}`);
    const state=await status.json();
    await rpc('apply_collection_heat',{p_heat:state.heat??null});
    await rpc('finish_snapshot_publication',{p_token:lease});
    return Response.json({skipped:'daily export budget exhausted',resume_on:batch.resume_on});
   }
   let batch=await rpc('export_snapshot_batch');
   if(batch.budget_exhausted)return await budgetPause(batch);
   let response=await send(batch);
   if(response.status===409){
    batch=await rpc('export_snapshot_batch',{p_force_full:true});
    if(batch.budget_exhausted)return await budgetPause(batch);
    response=await send(batch);
   }
   if(!response.ok)throw Error(`Incremental sync failed: HTTP ${response.status}`);
   const result=await response.json();
   if(result.acknowledged_revision!==batch.revision)throw Error('Unexpected sync acknowledgement');
   await rpc('ack_snapshot_batch',{p_revision:batch.revision});
   await rpc('apply_collection_heat',{p_heat:result.heat??null});
   await rpc('finish_snapshot_publication',{p_token:lease,p_version:result.publication?.revision===batch.revision?result.publication.version:null});
   console.log(JSON.stringify({trigger:'publish-incremental-snapshot',revision:batch.revision,schema:batch.schema,full:batch.full,sync_bytes:syncBytes,changes:batch.changes.length}));
   return Response.json({revision:batch.revision,publication:result.publication,changes:batch.changes.length,sync_bytes:syncBytes});
  }
  const snapshot=await buildSnapshot(await rpc('build_public_snapshot'));
  const previous=await retainCurrentSnapshot();
  await publishAssets({...previous,...snapshot.files},publishToken!);
  await rpc('finish_snapshot_publication',{p_token:lease,p_version:snapshot.manifest.version});
  console.log(JSON.stringify({trigger:'publish-public-snapshot',version:snapshot.manifest.version,offers:snapshot.manifest.offers.count,transit:snapshot.manifest.transit.count}));
  return Response.json({version:snapshot.manifest.version,generated_at:snapshot.manifest.generated_at});
 }catch(error){
  console.error(error);
  if(lease)try{await rpc('finish_snapshot_publication',{p_token:lease});}catch{}
  return Response.json({error:'Snapshot publication failed; previous publication retained'},{status:500});
 }
});
