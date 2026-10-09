import { SNAPSHOT_HEADERS } from './build.ts';
import { validateManifest } from '../src/data/snapshot.ts';
export const ACCOUNT_ID = 'c1ce7f8d4d7018d071afb6b70f29b787';
export const SNAPSHOT_WORKER = 'pricemapai-public-snapshots';
const apiBase = `https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers`;
export async function publishAssets(files: Record<string,Uint8Array<ArrayBuffer>>, token: string, fetcher: typeof fetch = fetch) {
  const manifest: Record<string,{hash:string;size:number}> = {};
  const contents = new Map<string,{bytes:Uint8Array<ArrayBuffer>;type:string}>();
  for (const [path, content] of Object.entries(files)) {
    if (!/^\/data\/(latest\.json|v\/[a-f0-9]{24}\/(offers|transit)-\d+\.json\.gz)$/.test(path)) throw Error('Invalid snapshot asset path');
    const bytes = content;
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const hash = Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2,'0')).join('').slice(0,32);
    manifest[path] = {hash,size:bytes.length};
    contents.set(hash,{bytes:content,type:path.endsWith('.gz')?'application/octet-stream':'application/json'});
  }
  async function call(path:string, init:RequestInit, credential=token) {
    const response = await fetcher(`${apiBase}${path}`, {...init, headers:{...Object.fromEntries(new Headers(init.headers)),Authorization:`Bearer ${credential}`}, signal:AbortSignal.timeout(30000)});
    const data = await response.json() as any;
    if (!response.ok || data.success === false) throw Error(`Cloudflare snapshot publishing failed: HTTP ${response.status}, codes ${(data.errors??[]).map((e:any)=>e.code).join(',')}`);
    return data.result;
  }
  const session = await call(`/scripts/${SNAPSHOT_WORKER}/assets-upload-session`, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({manifest})});
  let completion = session.jwt;
  for (const bucket of session.buckets as string[][]) {
    const form = new FormData();
    for (const hash of bucket) {
      const content = contents.get(hash);
      if (content == null) throw Error('Unknown requested snapshot hash');
      const bytes = content.bytes;
      // Avoid argument-count limits for multi-megabyte JSON pages.
      let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));
      form.set(hash,new Blob([btoa(binary)],{type:content.type}),hash);
    }
    const result = await call('/assets/upload?base64=true',{method:'POST',body:form},session.jwt);
    if (result?.jwt) completion=result.jwt;
  }
  if (!completion) throw Error('Missing asset completion token');
  const form = new FormData();
  form.set('metadata',JSON.stringify({compatibility_date:'2026-10-07',assets:{jwt:completion,config:{not_found_handling:'none',_headers:SNAPSHOT_HEADERS}}}));
  // This assets-only Worker has no executable script, database bindings or secrets.
  // The API switches its complete asset manifest only after all uploads succeed.
  await call(`/scripts/${SNAPSHOT_WORKER}`,{method:'PUT',body:form});
}
export async function retainCurrentSnapshot(fetcher: typeof fetch=fetch): Promise<Record<string,Uint8Array<ArrayBuffer>>> {
  const latest = await fetcher('https://pricemapai.com/data/latest.json',{cache:'no-store',signal:AbortSignal.timeout(10000)});
  if (latest.status === 404) return {};
  if (!latest.ok) throw Error('Cannot read currently published snapshot');
  const manifest = validateManifest(await latest.json());
  const files:Record<string,Uint8Array<ArrayBuffer>>={};
  for(const path of [...manifest.offers.pages,...manifest.transit.pages]) {
    const response=await fetcher(`https://pricemapai.com${path}`,{signal:AbortSignal.timeout(10000)});
    if(!response.ok)throw Error('Cannot retain the current snapshot');
    files[path]=new Uint8Array(await response.arrayBuffer());
  }
  return files;
}
