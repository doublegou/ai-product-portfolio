import { timingSafeEqual } from 'node:crypto';
import { crawlTransit } from '../../../worker/transit-crawl.ts';
import { collectTransit, validateTransitSource } from '../../../worker/transit.ts';
Deno.serve(async(request:Request)=>{
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'',token=Deno.env.get('CRAWLER_TOKEN')??'';
 const expected=new TextEncoder().encode(token),actual=new TextEncoder().encode(request.headers.get('X-Crawler-Token')??'');
 if(!key||!token||expected.length!==actual.length||!timingSafeEqual(expected,actual))return Response.json({error:'Unauthorized'},{status:401});
 if(request.method!=='POST')return new Response(null,{status:405});
 try {
  const text=await request.text();if(text.length>16000)return Response.json({error:'Request too large'},{status:413});
  const body=JSON.parse(text);
  if(body.preview){const s=validateTransitSource(body.preview);const snapshot=await collectTransit({...s,id:'preview'});return Response.json({count:snapshot.prices.length,complete:true,prices:snapshot.prices.slice(0,10)});}
  if(body.source_id!=null&&(typeof body.source_id!=='string'||!/^[a-z0-9-]{1,100}$/.test(body.source_id)))return Response.json({error:'Invalid source'},{status:400});
  const results=await crawlTransit({SUPABASE_URL:Deno.env.get('SUPABASE_URL')!,SUPABASE_SERVICE_ROLE_KEY:key},body.source_id);
  console.log(JSON.stringify({trigger:'original-transit-collection',sources:results.length,failed:results.filter(r=>r.status==='failed').length}));
  return Response.json({results});
 } catch(e){console.error(e);return Response.json({error:e instanceof Error?e.message:'Collection failed'},{status:500});}
});
