import {readSnapshotPages} from './snapshot';
import type {TransitStation,PublicMonitoring} from '../lib/apiTransit';
type Fetcher=typeof fetch;
const validDate=(v:unknown):v is string=>typeof v==='string'&&Number.isFinite(Date.parse(v));
function checkMonitor(m:PublicMonitoring|undefined,expired:boolean){if(!m)return m;return {...m,stale:expired||!!m.updatedAt&&Date.parse(m.updatedAt)<Date.now()-24*3600000};}
export async function loadTransit(fetcher:Fetcher=fetch,signal?:AbortSignal):Promise<TransitStation[]> {
 const result:TransitStation[]=[],seen=new Set<string>();
 const rows=await readSnapshotPages('transit',fetcher,signal);
  for(const value of rows){
   const row=value as any;
   const s=row.data as TransitStation;
   if(!s||typeof s.id!=='string'||s.id!==row.source_id||seen.has(s.id)||!s.name||!Array.isArray(s.prices)||!s.prices.length||!validDate(row.last_seen_at)||!validDate(row.expires_at))throw Error('API 报价不完整');
   seen.add(s.id);const expired=Date.parse(row.expires_at)<=Date.now();
   result.push({...s,lastUpdatedAt:row.last_seen_at,expiresAt:row.expires_at,collectionError:row.collection_error===true,publicMonitoring:checkMonitor(s.publicMonitoring,expired),
    prices:s.prices.map(p=>({...p,lastVerifiedAt:row.last_seen_at,expiresAt:row.expires_at,publicMonitoring:checkMonitor(p.publicMonitoring,expired)}))});
  }
 return result;
}
