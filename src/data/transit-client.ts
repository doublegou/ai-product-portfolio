import type {TransitStation,PublicMonitoring} from '../lib/apiTransit';
type Fetcher=typeof fetch;
const validDate=(v:unknown):v is string=>typeof v==='string'&&Number.isFinite(Date.parse(v));
function checkMonitor(m:PublicMonitoring|undefined,expired:boolean){if(!m)return m;return {...m,stale:expired||!!m.updatedAt&&Date.parse(m.updatedAt)<Date.now()-24*3600000};}
export async function loadTransit(fetcher:Fetcher=fetch,signal?:AbortSignal):Promise<TransitStation[]> {
 const result:TransitStation[]=[],seen=new Set<string>();let offset:number|null=0;let expected:number|undefined;
 while(offset!=null){
  const response:Response=await fetcher(`/api/transit?limit=2&offset=${offset}`,{signal});
  if(!response.ok)throw Error('API 报价暂时无法读取，请稍后重试');
  const page:any=await response.json();
  if(!Array.isArray(page.stations)||!Number.isInteger(page.total)||page.total<0||page.total>2000)throw Error('API 报价数据格式异常');
  if(expected!==undefined&&page.total!==expected)throw Error('来源列表正在更新，请稍后重试');expected=page.total;
  for(const row of page.stations){
   const s=row.data as TransitStation;
   if(!s||typeof s.id!=='string'||s.id!==row.source_id||seen.has(s.id)||!s.name||!Array.isArray(s.prices)||!s.prices.length||!validDate(row.last_seen_at)||!validDate(row.expires_at))throw Error('API 报价不完整');
   seen.add(s.id);const expired=Date.parse(row.expires_at)<=Date.now();
   result.push({...s,lastUpdatedAt:row.last_seen_at,expiresAt:row.expires_at,collectionError:row.collection_error===true,publicMonitoring:checkMonitor(s.publicMonitoring,expired),
    prices:s.prices.map(p=>({...p,lastVerifiedAt:row.last_seen_at,expiresAt:row.expires_at,publicMonitoring:checkMonitor(p.publicMonitoring,expired)}))});
  }
  const next:number|null=page.next_offset;
  if(next!==null&&(!Number.isSafeInteger(next)||next!==offset+page.stations.length||next<=offset||next>=expected!))throw Error('API 分页中断');
  offset=next;
 }
 if(result.length!==expected)throw Error('API 报价未完整加载');
 return result;
}
