import { merchantLink } from '../src/lib/merchant-links.ts';
// Defense in depth: never publish collector configs, raw responses, credentials,
// leases or error messages even if unexpected fields enter the stored payload.
const pick=(value:any,keys:string)=>Object.fromEntries(keys.split(' ').filter(key=>Object.hasOwn(value??{},key)).map(key=>[key,value[key]]));
const monitoring=(value:any)=>value==null?value:{...pick(value,'rate samples latencyMs latencyLabel scope sourceUrl updatedAt tokensPerSecond cacheHitRate throughputLabel aggregation stale'),history:Array.isArray(value.history)?value.history.map((row:any)=>pick(row,'rate samples at')):[]};
export function publicTransitRows(rows:any[]):any[] {
 return rows.map(row=>{
  const s=row.data;
  if(!s||typeof row.source_id!=='string'||s.id!==row.source_id||!s.name||!Array.isArray(s.prices)||!s.prices.length||
    !Number.isFinite(Date.parse(row.last_seen_at))||!Number.isFinite(Date.parse(row.expires_at)))throw Error('Invalid transit snapshot');
  const data=pick(s,'id name websiteUrl logoUrl summary channelTypes monitorUrl lastUpdatedAt pricingUrl expiresAt sourceUpdatedAt');
  data.prices=s.prices.map((price:any)=>{
   const p=pick(price,'id expiresAt sourceUpdatedAt rechargeCurrency creditCurrency comparisonEligible billingMode priceBasis family standardModel groupName rechargeRatio modelMultiplier fixedPrice fixedPriceUnit inputPrice outputPrice currency accountPool channelType lastVerifiedAt sevenDayRate sevenDaySamples recentSampleBits latestLatencyMs avgLatency7dMs lastCheckedAt monitoringScopeId scope originalModel note sourceLabel sourceUrl requestWindowHours');
   if(price.publicMonitoring)p.publicMonitoring=monitoring(price.publicMonitoring);
   if(price.cacheUsage)p.cacheUsage=pick(price.cacheUsage,'hitRate sampleTokens');
   return p;
  });
  if(s.publicMonitoring)data.publicMonitoring=monitoring(s.publicMonitoring);
  if(s.info)data.info=pick(s.info,'minimumTopUp stationSystem invoiceSupport operatorType refundPolicy balanceExpiry paymentMethods supportChannels');
  if(s.availability)data.availability=pick(s.availability,'sevenDayRate sevenDaySamples recentSampleBits avgLatency7dMs note sourceUrl sourceLabel');
  if(s.performance)data.performance=pick(s.performance,'tokensPerSecond latencyMs scope sourceUrl updatedAt');
  return {...pick(row,'source_id last_seen_at expires_at collection_error'),data};
 });
}
export function publicOfferRows(rows:any[]):any[] {
 return rows.map(row=>({...pick(row,'id raw_title platform plan delivery duration_days comparison_key review_required price currency stock_status purchase_url last_seen_at expires_at price_note stock_quantity stock_text'),
  purchase_url:merchantLink(row.purchase_url)??row.purchase_url,
  sources:{...pick(row.sources,'name base_url'),base_url:merchantLink(row.sources?.base_url)??row.sources?.base_url}}));
}
