import { timingSafeEqual } from 'node:crypto';
import { buildSnapshot } from '../../../snapshot/build.ts';
import { publishAssets, retainCurrentSnapshot } from '../../../snapshot/publish.ts';
Deno.serve(async(request:Request)=>{
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'',token=Deno.env.get('CRAWLER_TOKEN')??'';
 const expected=new TextEncoder().encode(token),actual=new TextEncoder().encode(request.headers.get('X-Crawler-Token')??'');
 if(!key||!token||expected.length!==actual.length||!timingSafeEqual(expected,actual))return Response.json({error:'Unauthorized'},{status:401});
 if(request.method!=='POST')return new Response(null,{status:405});
 const publishToken=Deno.env.get('CLOUDFLARE_SNAPSHOT_API_TOKEN');
 if(!publishToken)return Response.json({error:'Publisher credential not configured'},{status:503});
 async function rpc(name:string,body:unknown={}) {
  const r=await fetch(`${Deno.env.get('SUPABASE_URL')}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
  if(!r.ok)throw Error(`Snapshot database operation failed: ${name}, HTTP ${r.status}`);
  if(r.status===204)return null;
  const text=await r.text();return text?JSON.parse(text):null;
 }
 let lease:string|null=null;
 try {
  lease=await rpc('claim_snapshot_publication');
  if(!lease)return Response.json({skipped:'publication already running'});
  const snapshot=await buildSnapshot(await rpc('build_public_snapshot'));
  const previous=await retainCurrentSnapshot();
  await publishAssets({...previous,...snapshot.files},publishToken);
  await rpc('finish_snapshot_publication',{p_token:lease,p_version:snapshot.manifest.version});
  console.log(JSON.stringify({trigger:'publish-public-snapshot',version:snapshot.manifest.version,offers:snapshot.manifest.offers.count,transit:snapshot.manifest.transit.count}));
  return Response.json({version:snapshot.manifest.version,generated_at:snapshot.manifest.generated_at});
 }catch(error){
  console.error(error);
  if(lease)try{await rpc('finish_snapshot_publication',{p_token:lease});}catch{}
  return Response.json({error:'Snapshot publication failed; previous publication retained'},{status:500});
 }
});
