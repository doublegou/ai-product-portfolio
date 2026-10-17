// Relay sources are connected independently of the subscription collector.
export type PublicMonitoring = {
  rate: number | null; samples: number | null; latencyMs: number | null; latencyLabel: string;
  scope: string; sourceUrl: string; updatedAt: string | null;
  tokensPerSecond?: number | null; cacheHitRate?: number | null;
  throughputLabel?: string; aggregation?: string;
  history: { rate: number | null; samples: number | null; at: string | null }[];
  stale?: boolean;
};
export type TransitPrice = {
  id?: string; expiresAt?: string; sourceUpdatedAt?: string | null;
  rechargeCurrency?: string | null; creditCurrency?: string | null;
  comparisonEligible?: boolean; billingMode?: string; priceBasis?: string;
  family: string | null; standardModel: string | null; groupName: string | null;
  rechargeRatio: string | null; modelMultiplier: number | null; fixedPrice: number | null;
  fixedPriceUnit: string | null; inputPrice: number | null; outputPrice: number | null;
  currency: string | null; accountPool: string | null; channelType: string | null;
  lastVerifiedAt: string | null; sevenDayRate: number | null; sevenDaySamples: number | null;
  cacheUsage?: { hitRate: number; sampleTokens: number } | null;
  recentSampleBits?: string | null; latestLatencyMs?: number | null; avgLatency7dMs?: number | null;
  lastCheckedAt?: string | null; monitoringScopeId?: string | null; scope?: string | null;
  publicMonitoring?: PublicMonitoring; originalModel?: string;
  note: string | null; sourceLabel: string | null; sourceUrl: string | null; requestWindowHours: number | null;
};
export type TransitStation = {
  expiresAt?: string; sourceUpdatedAt?: string | null; collectionError?: boolean;
  id: string; name: string; websiteUrl: string | null; logoUrl?: string | null;
  summary: string | null; channelTypes: string[]; monitorUrl?: string | null;
  lastUpdatedAt: string | null;
  prices: TransitPrice[]; pricingUrl?: string; publicMonitoring?: PublicMonitoring;
  monitoringError?: string;
  info?: { minimumTopUp: string | null; stationSystem: string | null; invoiceSupport: string | null;
    operatorType: string | null; refundPolicy: string | null; balanceExpiry: string | null;
    paymentMethods: string[]; supportChannels: string[] };

  availability?: { sevenDayRate: number | null; sevenDaySamples: number; recentSampleBits?: string | null; avgLatency7dMs?: number | null; note?: string | null; sourceUrl?: string | null; sourceLabel?: string | null } | null;
  performance?: { tokensPerSecond: number | null; latencyMs: number | null; scope: string; sourceUrl: string; updatedAt: string | null };
};
export const apiFamilies: { id: string; label: string; logo: string; officialOnly?: boolean }[] = [
  { id: '', label: '全部', logo: '' },
  { id: 'gpt', label: 'ChatGPT', logo: '/logos/openai.svg' },
  { id: 'claude', label: 'Claude', logo: '/logos/claude-color.svg' },
  { id: 'gemini', label: 'Gemini', logo: '/logos/gemini-color.svg' },
  { id: 'grok', label: 'Grok', logo: '/logos/grok.svg' },
  { id: 'deepseek', label: 'DeepSeek', logo: '/logos/deepseek-color.svg' },
  { id: 'kimi', label: 'Kimi', logo: '/logos/moonshot.svg' },
  { id: 'qwen', label: '千问', logo: '/logos/qwen-color.svg' },
  { id: 'glm', label: 'GLM', logo: '/logos/zhipu-color.svg' },
  { id: 'mimo', label: '小米 MiMo', logo: '/logos/xiaomimimo.svg', officialOnly: true },
  { id: 'doubao', label: '豆包', logo: '/logos/doubao-color.svg', officialOnly: true },
  { id: 'minimax', label: 'MiniMax', logo: '/logos/minimax-color.svg', officialOnly: true },
  { id: 'hunyuan', label: '混元', logo: '/logos/hunyuan-color.svg', officialOnly: true },
  { id: 'image', label: '图片生成', logo: '' },
  { id: 'video', label: '视频生成', logo: '' },
];
export const channelLabels: Record<string,string> = { official_api: '官方 API', reverse_engineered: '逆向渠道', reseller: '渠道商', cloud: '云平台', first_party_wholesale: '一手渠道', first_party_pool: '一手号池', mixed: '混合渠道', undisclosed: '未披露' };
export function rechargeFactor(ratio: string | null) {
  const parts = ratio?.match(/(\d+(?:\.\d+)?)\s*:\s*(\d+(?:\.\d+)?)/)
    ?? ratio?.match(/(\d+(?:\.\d+)?)\s*(?:CNY|USD|RMB|人民币|元|￥|¥)?\s*=\s*(\d+(?:\.\d+)?)/i);
  if(parts&&Number(parts[2])>0)return Number(parts[1])/Number(parts[2]);
  const reverse=ratio?.match(/^(\d+(?:\.\d+)?) USD balance per (\d+(?:\.\d+)?) CNY$/i);
  return reverse&&Number(reverse[1])>0?Number(reverse[2])/Number(reverse[1]):null;
}
export function combinedRate(price?: TransitPrice) {
  if (!price || price.comparisonEligible !== true || isTransitStale(price)) return null;
  const factor = rechargeFactor(price.rechargeRatio);
  return price.fixedPrice == null && !['image','video'].includes(price.family ?? '') && factor != null && price.modelMultiplier != null
    ? factor * price.modelMultiplier : null;
}
export function rate(value: number | null) { return value == null ? '—' : `${Number(value.toFixed(3))}×`; }
export function isTransitStale(value: {expiresAt?:string}, now=Date.now()) { return !!value.expiresAt && Date.parse(value.expiresAt)<=now; }
export function money(value:number|null,currency:string|null) {return value==null?'—':`${currency==='CNY'?'¥':currency==='USD'?'$':'额度 $'}${Number(value.toFixed(5))}`;}
export function isTieredPrice(price?:TransitPrice) {
  // Older stored snapshots identify interval pricing in the normalized note.
  return !!price && (/tier|expr/.test(price.billingMode??'') || price.note?.startsWith('阶梯计费，具体档位请查看原站')===true);
}
export function priceMetric(price?: TransitPrice) {
  if (!price) return '分组定价';
  if(isTransitStale(price))return '待更新';
  return price.fixedPrice != null ? `${money(price.fixedPrice,price.currency)}/${price.fixedPriceUnit === 'image' ? '张' : price.fixedPriceUnit === 'second' ? '秒' : '次'}` : rate(combinedRate(price));
}
export function bestPrice(prices: TransitPrice[]) {
  return prices.filter(p=>combinedRate(p)!=null).sort((a,b)=>combinedRate(a)!-combinedRate(b)!)[0];
}
export function availability(price?: TransitPrice) {
  return price && (price.sevenDaySamples ?? 0) > 0 && price.sevenDayRate != null ? `${(price.sevenDayRate * 100).toFixed(1)}%` : '—';
}

export function multiplierRange(values: (number | null)[]) {
  const finite = values.filter((v): v is number => v != null && Number.isFinite(v) && v > 0);
  if (!finite.length) return '—';
  const min = Math.min(...finite), max = Math.max(...finite);
  return min === max ? rate(min) : `${Number(min.toFixed(3))}–${Number(max.toFixed(3))}×`;
}
export function quoteMonitoring(price?: TransitPrice): PublicMonitoring | undefined {
  if (!price) return;
  if (price.publicMonitoring) return freshMonitoring(price.publicMonitoring,isTransitStale(price));
  if(price.sevenDayRate==null&&price.sevenDaySamples==null&&!price.recentSampleBits)return;
  const window = price.requestWindowHours ? `${price.requestWindowHours} 小时` : price.note?.match(/(\d+)\s*(小时|日)/)?.[0] ?? '公开监测';
  return {
    rate: price.sevenDayRate, samples: price.sevenDaySamples,
    latencyMs: price.avgLatency7dMs ?? null,
    latencyLabel: price.sourceLabel?.includes('被动') ? '首字延迟' : '探测延迟',
    scope: `${price.scope === 'station' ? '全站' : price.note?.includes('分组') ? '分组' : '对应报价'} · ${window}`,
    sourceUrl: price.sourceUrl ?? '', updatedAt: price.lastCheckedAt ?? price.lastVerifiedAt,
    history: [...(price.recentSampleBits ?? '')].map(bit => ({ rate: bit === '1' ? 1 : bit === '0' ? 0 : null, samples: 1, at: null })),
  };
}
export function percent(value?: number | null) { return value == null ? '—' : `${(value * 100).toFixed(1)}%`; }
export function seconds(ms?: number | null) { return ms == null ? '—' : `${(ms / 1000).toFixed(2)} s`; }

/** Prefer the public whole-station scope in an overview, independent of its cheapest quote. */
export function stationMonitoring(station: TransitStation): PublicMonitoring | undefined {
  if (station.publicMonitoring) return freshMonitoring(station.publicMonitoring,isTransitStale(station));
  const source = station.availability;
  if (!source) return;
  const window = source.note?.match(/(\d+)\s*(小时|日)/)?.[0] ?? '公开监测';
  return { rate: source.sevenDayRate, samples: source.sevenDaySamples,
    latencyMs: source.avgLatency7dMs ?? null,
    latencyLabel: source.sourceLabel?.includes('被动') ? '首字延迟' : '探测延迟',
    scope: `全站 · ${window}`, sourceUrl: source.sourceUrl ?? station.monitorUrl ?? '', updatedAt: station.lastUpdatedAt,
    history: [...(source.recentSampleBits ?? '')].map(bit => ({ rate: bit === '1' ? 1 : bit === '0' ? 0 : null, samples: 1, at: null })),
    tokensPerSecond: station.performance?.tokensPerSecond,
  };
}
export function stationCache(station: TransitStation, prices: TransitPrice[]) {
  if(isTransitStale(station))return {value:'—',scope:'数据待更新'};
  if ((station.publicMonitoring?.samples ?? 0) > 0 && station.publicMonitoring?.cacheHitRate != null && !station.publicMonitoring.stale) {
    return { value: percent(station.publicMonitoring.cacheHitRate), scope: station.publicMonitoring.scope };
  }
  const groups = new Map<string, number>();
  for (const p of prices) if (p.cacheUsage && p.cacheUsage.sampleTokens > 0) groups.set(p.groupName ?? '', p.cacheUsage.hitRate);
  const values = [...groups.values()].filter(Number.isFinite);
  const value = !values.length ? '—' : Math.min(...values) === Math.max(...values) ? percent(values[0]) : `${(Math.min(...values) * 100).toFixed(1)}–${(Math.max(...values) * 100).toFixed(1)}%`;
  return { value, scope: values.length ? '公开分组范围' : '未公开' };
}
export function modelSourceUrl(station: TransitStation, price: TransitPrice) {
  // Source sites without stable model anchors receive a valid pricing-page link.
  // Do not invent a query parameter that their frontend ignores.
  return station.pricingUrl ?? station.websiteUrl ?? price.sourceUrl ?? '';
}

function freshMonitoring(m:PublicMonitoring,expired:boolean):PublicMonitoring {
 if(!expired&&!m.stale&&(!m.updatedAt||Date.parse(m.updatedAt)>=Date.now()-24*3600000))return m;
 return {...m,rate:null,latencyMs:null,tokensPerSecond:null,cacheHitRate:null,history:[],stale:true,scope:`${m.scope} · 待更新`};
}
