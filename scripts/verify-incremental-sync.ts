import {workerEnv,clientFor} from './shared.ts';
import {mergeBatch,publicSnapshot} from '../snapshot/incremental.ts';
import {buildSnapshot} from '../snapshot/build.ts';
const env=workerEnv(),client=clientFor(env);
async function rpc(name:string,args:Record<string,unknown>={}){
 const {data,error}=await client.rpc(name,args);if(error)throw Error(`${name}: ${error.message}`);return data;
}
let batch=await rpc('export_snapshot_batch');
if(batch.budget_exhausted)throw Error('Daily export budget exhausted');
const endpoint='https://pricemapai-snapshot-sync.newbee.workers.dev/sync';
async function send(){return fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json','X-Crawler-Token':process.env.CRAWLER_TOKEN!},body:JSON.stringify(batch),signal:AbortSignal.timeout(120000)});}
let response=await send();
if(response.status===409){batch=await rpc('export_snapshot_batch',{p_force_full:true});if(batch.budget_exhausted)throw Error('Daily export budget exhausted');response=await send();}
if(!response.ok)throw Error(`Sync HTTP ${response.status}: ${await response.text()}`);
const result=await response.json() as any;
if(result.acknowledged_revision!==batch.revision)throw Error('Wrong acknowledged revision');
if(batch.full){
 const expected=await buildSnapshot(publicSnapshot(mergeBatch(null,batch)));
 if(result.publication?.version!==expected.manifest.version)throw Error('Static publication does not match full export');
 console.log(JSON.stringify({revision:batch.revision,bytes:Buffer.byteLength(JSON.stringify(batch)),changes:batch.changes.length,offers:expected.manifest.offers.count,transit:expected.manifest.transit.count,version:result.publication.version}));
}else console.log(JSON.stringify({revision:batch.revision,bytes:Buffer.byteLength(JSON.stringify(batch)),changes:batch.changes.length,publication:result.publication}));
await rpc('ack_snapshot_batch',{p_revision:batch.revision});
