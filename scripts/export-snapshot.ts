import { mkdir, writeFile, rm } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { workerEnv, clientFor } from './shared';
import { buildSnapshot, SNAPSHOT_HEADERS } from '../snapshot/build';
import { retainCurrentSnapshot } from '../snapshot/publish';
const env=workerEnv();
const {data,error}=await clientFor(env).rpc('build_public_snapshot');
if(error)throw Error(`Snapshot export failed: ${error.message}`);
const {files,manifest}=await buildSnapshot(data);
const directory=resolve('artifacts/snapshot-assets');
const previous=process.argv.includes('--initial')?{}:await retainCurrentSnapshot();
await rm(directory,{recursive:true,force:true});
for(const [path,content]of Object.entries({...previous,...files})){
 const output=resolve(directory,'.'+path);await mkdir(dirname(output),{recursive:true});await writeFile(output,content);
}
await writeFile(resolve(directory,'_headers'),SNAPSHOT_HEADERS);
console.log(JSON.stringify({version:manifest.version,generated_at:manifest.generated_at,offers:manifest.offers.count,transit:manifest.transit.count}));
