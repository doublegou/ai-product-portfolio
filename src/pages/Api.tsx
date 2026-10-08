import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { ArrowUpRight, ChevronLeft, ChevronRight, LayoutGrid, List, Network, Building2 } from 'lucide-react';
import { SearchField } from '../components/SearchField';
import { CategoryIcon } from '../components/CategoryIcon';
import { GlassSelect } from '../components/GlassSelect';
import { EmptyState } from '../components/ProductList';
import { Pagination } from '../components/Pagination';
import { apiProviders } from '../data/api';
import { apiFamilies, isTieredPrice, isTransitStale, money, bestPrice, rate, rechargeFactor, priceMetric, combinedRate, channelLabels, multiplierRange, quoteMonitoring, percent, seconds, stationMonitoring, stationCache, modelSourceUrl, type PublicMonitoring, type TransitStation, type TransitPrice } from '../lib/apiTransit';
import { DataUpdated } from '../components/DataUpdated';
import { useStickyStack } from '../lib/useStickyStack';
import '../api.css';
import {useTransit} from '../lib/useTransit';

function ApiLogo({name,src}:{name:string;src?:string|null}) {
  const [failed,setFailed] = useState(false);
  useEffect(()=>setFailed(false),[src]);
  return src && !failed ? <img className="api-logo" src={src} alt="" loading="lazy" referrerPolicy="no-referrer" onError={()=>setFailed(true)}/>
    : <span className="merchant-logo merchant-logo-fallback" aria-hidden="true">{(name.match(/[\p{L}\p{N}]/u)?.[0]??'?').toUpperCase()}</span>;
}
function FamilyLogo({id}:{id:string}) {
  const family=apiFamilies.find(f=>f.id===id);
  return family?.logo ? <img className="api-family-logo" src={family.logo} alt=""/> : <CategoryIcon category={id || 'all'} size={21}/>;
}
function StationIdentity({station,showUrl=false}:{station:TransitStation;showUrl?:boolean}) {
  const src=station.logoUrl?.startsWith('https://') ? station.logoUrl : undefined;
  return <span className="api-identity"><ApiLogo name={station.name} src={src}/><span><strong>{station.name}</strong>{showUrl&&<small>{new URL(station.websiteUrl!).hostname.replace(/^www\./,'')}</small>}</span></span>;
}
function PurchaseLink({url}:{url:string}) { return <a className="api-site-link" href={url} target="_blank" rel="noreferrer">访问原站<ChevronRight size={15}/></a>; }
function DirectoryMetrics({prices,detail=false}:{prices:TransitPrice[];detail?:boolean}) {
  const best=detail?prices[0]:bestPrice(prices);
  const ratios=[...new Set(prices.map(p=>p.rechargeRatio).filter(Boolean))].map(r=>{
    const parts=r!.match(/(\d+(?:\.\d+)?)\s*:\s*(\d+(?:\.\d+)?)/);
    const explicit=r!.match(/(\d+(?:\.\d+)?)\s*(CNY|USD)\s*=\s*(\d+(?:\.\d+)?)\s*(CNY|USD)/i);
    return parts?`¥${parts[1]} = $${parts[2]}`:explicit?`${explicit[2]==='CNY'?'¥':'$'}${explicit[1]} = ${explicit[4]==='CNY'?'¥':'$'}${explicit[3]}`:r;
  });
  const rechargeValue=[multiplierRange(prices.map(p=>p.currency==='USD_CREDIT'?null:rechargeFactor(p.rechargeRatio))),...ratios].join(' · ');
  const recharge=<div className="api-directory-recharge" title="原站公开的充值金额与计价额度换算，非货币汇率；币种以标注为准"><span>充值系数</span><strong className="api-rate-value">{rechargeValue}</strong></div>;
  if(detail) return <div className="api-single-rates" title={[best?.note,best?.sourceUpdatedAt?`原站快照时间：${new Date(best.sourceUpdatedAt).toLocaleString('zh-CN')}`:null].filter(Boolean).join('；')}><div><span>{best?.fixedPrice!=null?'固定价':'模型倍率'}</span><strong className="api-rate-value">{best?.fixedPrice!=null?priceMetric(best):rate(best?.modelMultiplier??null)}</strong></div>{recharge}{best&&<small className="api-token-cost">{isTieredPrice(best)?'阶梯计费 · 见原站':best.fixedPrice!=null?null:<>输入 {money(best.inputPrice,best.currency)} / 输出 {money(best.outputPrice,best.currency)}<br/>每百万 Token</>}{best.note&&<span className="api-price-note">{best.note}</span>}</small>}</div>;
  return <div className="api-directory-rates"><div className="api-rate-head"><span><small className="api-rate-label">{best?'最低综合系数':'原站报价'}</small><small className="api-best-model" title={best?.standardModel??''}>{best?.standardModel??'按模型 / 分组查看'}</small></span><strong className="api-rate-value">{priceMetric(best)}</strong></div>{recharge}<div><span>模型倍率</span><strong className="api-rate-value">{multiplierRange(prices.filter(p=>p.fixedPrice==null).map(p=>p.modelMultiplier))}</strong></div></div>;
}
function MonitoringSummary({monitor}:{monitor?:PublicMonitoring}) {
  const valid=!!monitor&&!monitor.stale&&monitor.samples!==0&&monitor.rate!=null;
  const history=monitor?.history.slice(-30)??[];
  return <div className="api-monitor-summary" title={monitor ? `${monitor.scope}${monitor.aggregation ? ` · ${monitor.aggregation}` : ""}${monitor.updatedAt ? ` · 监测更新 ${new Date(monitor.updatedAt).toLocaleString('zh-CN')}` : ''}` : undefined}><div className="api-monitor-top"><strong className={valid?`api-availability ${monitor!.rate!>=.98?'healthy':monitor!.rate!>=.9?'warning':'failed'}`:''}>{valid?percent(monitor?.rate):'—'}</strong>{monitor?.sourceUrl&&<a href={monitor.sourceUrl} target="_blank" rel="noreferrer" aria-label="查看监测来源"><ArrowUpRight size={13}/></a>}</div>{history.length>0?<div className="api-health-bars" role="img" aria-label={`近期监测记录，${history.length} 个样本或时段`}>{history.map((point,i)=><span key={i} className={point.rate==null?'unknown':point.rate>=.98?'healthy':point.rate>=.9?'warning':'failed'} style={{height:point.rate==null?6:Math.max(4,point.rate*18)}} title={`${point.at?new Date(point.at).toLocaleString('zh-CN'): `样本 ${i+1}`} · ${point.samples===0?'无请求':point.rate==null?'无数据':percent(point.rate)}${point.samples&&point.samples>1?` · ${point.samples} 次请求`:''}`}/>)}</div>:<div className="api-health-empty" title={valid?"来源仅公开汇总值，未公开可绘图的逐次或逐时记录":"该范围未公开有效监测数据"}>{valid?"仅公开汇总值":"未公开记录"}</div>}<small>{monitor?.scope??'未公开监测'}</small>{monitor?.aggregation&&<small>{monitor.aggregation}</small>}</div>;
}
function CacheSummary({price,station,prices,hideScope=false}:{price?:TransitPrice;station?:TransitStation;prices?:TransitPrice[];hideScope?:boolean}) {
  const summary=station?stationCache(station,prices??station.prices):null;
  const cache=price&&!isTransitStale(price)?price.cacheUsage:null,monitor=quoteMonitoring(price);
  const value=summary?.value??(monitor?.cacheHitRate!=null?percent(monitor.cacheHitRate):cache&&cache.sampleTokens>0?percent(cache.hitRate):'—');
  const scope=summary?.scope??(monitor?.cacheHitRate!=null?monitor.scope:cache&&cache.sampleTokens>0?'分组数据':'未公开');
  return <div className="api-cache-summary" title={`${scope}${cache?` · ${price?.standardModel} / ${price?.groupName} · ${cache.sampleTokens.toLocaleString()} tokens`:''}`}><strong>{value}</strong>{!hideScope&&<small>{scope}</small>}</div>;
}
function PerformanceSummary({monitor}:{monitor?:PublicMonitoring}) {
  const tokens=monitor?.tokensPerSecond;
  return <div className="api-performance-summary"><div className="api-speed-pair"><span><small>吞吐</small><b>{tokens!=null?`${Intl.NumberFormat('en',{notation:'compact',maximumFractionDigits:1}).format(tokens)} tok/s`:monitor?.stale?'待更新':'未公开'}</b></span><span><small>{monitor?.latencyLabel??'延迟'}</small><b>{seconds(monitor?.latencyMs)}</b></span></div><small>{monitor?.scope??'未公开'}{tokens!=null?` · ${monitor?.throughputLabel??'总 Token 吞吐'}`:''}</small></div>;
}
function ModelOverview({prices,family}:{prices:TransitPrice[];family:string}) {
  const names=[...new Set(prices.map(p=>p.standardModel).filter((name):name is string=>!!name))];
  const families=apiFamilies.filter(f=>f.id&&prices.some(p=>p.family===f.id));
  return <div className="api-model-overview"><strong>{names.length} 个模型 · {prices.length} 条报价</strong>{family?<div className="api-model-preview" title={names.join(' · ')}>{names.slice(0,6).map(name=><span key={name}>{name}</span>)}{names.length>6&&<span>+{names.length-6}</span>}</div>:<div className="api-family-overview">{families.map(f=><span key={f.id}><FamilyLogo id={f.id}/>{f.label}</span>)}</div>}</div>;
}
const systemLabels:Record<string,string>={sub_to_api:'Sub2API',new_api:'New API',one_api:'One API',custom:'自建系统'};
function StationProfile({station,now}:{station:TransitStation;now:number}) {
  const info=station.info;
  return <article className="api-station-profile glass-surface"><div className="api-profile-main"><StationIdentity station={station} showUrl/><a className="api-site-link" href={station.websiteUrl!} target="_blank" rel="noreferrer">站点首页<ChevronRight size={17}/></a></div><div className="api-profile-tags">{info?.stationSystem&&<span className="api-profile-tag"><Building2 size={13}/>{systemLabels[info.stationSystem]??info.stationSystem}</span>}{info?.minimumTopUp&&<span className="api-profile-tag">最低充值 <b>{info.minimumTopUp}</b></span>}{info?.invoiceSupport&&info.invoiceSupport!=='unknown'&&<span className="api-profile-tag">{info.invoiceSupport==='supported'?'支持开票':'不支持开票'}</span>}{station.channelTypes.map(t=><span className="api-profile-tag" key={t}>{channelLabels[t]??t}</span>)}<span className="api-profile-tag api-profile-updated">{isTransitStale(station,now)?'待更新 · ':station.collectionError?'最近采集失败 · ':''}<DataUpdated at={station.lastUpdatedAt} now={now}/></span></div>{(info?.refundPolicy||info?.balanceExpiry)&&<p className="api-profile-policy">{[info.refundPolicy,info.balanceExpiry].filter(Boolean).join(' · ')}</p>}</article>;
}
function ModelIdentity({station,price}:{station:TransitStation;price:TransitPrice}) {
  return <div className="api-model-identity"><a href={modelSourceUrl(station,price)} target="_blank" rel="noreferrer" title={`查看原站报价 · ${price.originalModel??price.standardModel}。该来源未提供独立模型地址，需在原站搜索或展开分组。`}><strong>{price.standardModel}</strong><ArrowUpRight size={14}/></a><small className="api-group-name">{price.groupName||'默认分组'}</small></div>;
}
function ChannelSummary({station,price}:{station:TransitStation;price:TransitPrice}) {
  const disclosed=station.channelTypes.filter(t=>!['mixed','undisclosed'].includes(t)).map(t=>channelLabels[t]??t);
  return <div className="api-channel-summary"><span className={price.channelType==='mixed'?'api-channel-mixed':undefined}>{channelLabels[price.channelType??'']??'未披露'}</span>{price.channelType==='mixed'&&disclosed.length>0&&<small>{disclosed.join(' · ')}</small>}</div>;
}
function ModelAction({station,price}:{station:TransitStation;price:TransitPrice}) {
  return <a className="api-site-link api-model-action" href={modelSourceUrl(station,price)} target="_blank" rel="noreferrer" aria-label={`前往原站查看 ${price.standardModel} 报价`}>原站报价<ChevronRight size={15}/></a>;
}
function QuoteResults({station,prices,view,now}:{station:TransitStation;prices:TransitPrice[];view:string;now:number}) {
  if(view==='grid') return <div className="subscription-grid api-cards">{prices.map((p,i)=><article className="api-quote-card glass-surface" key={i}><ModelIdentity station={station} price={p}/><DirectoryMetrics prices={[p]} detail/><div className="api-card-telemetry"><div><small className="api-card-metric-label">缓存命中率</small><CacheSummary price={p} hideScope/></div><PerformanceSummary monitor={quoteMonitoring(p)}/></div><MonitoringSummary monitor={quoteMonitoring(p)}/><footer className="api-quote-meta"><ChannelSummary station={station} price={p}/><small><DataUpdated at={station.lastUpdatedAt} now={now}/></small></footer><ModelAction station={station} price={p}/></article>)}</div>;
  return <div className="catalog-table-wrap api-table-wrap"><table className="catalog-table api-quotes-table"><colgroup>{[16,16,11,14,13,10,8,12].map((w,i)=><col key={i} style={{width:`${w}%`}}/>)}</colgroup><thead><tr>{['模型 / 分组','倍率','缓存命中率','近期可用性','吞吐 / 延迟','渠道','更新','操作'].map(t=><th key={t} scope="col">{t}</th>)}</tr></thead><tbody>{prices.map((p,i)=><tr key={`${p.standardModel}-${p.groupName}-${i}`}><td><ModelIdentity station={station} price={p}/></td><td><DirectoryMetrics prices={[p]} detail/></td><td><CacheSummary price={p} hideScope/></td><td><MonitoringSummary monitor={quoteMonitoring(p)}/></td><td><PerformanceSummary monitor={quoteMonitoring(p)}/></td><td><ChannelSummary station={station} price={p}/></td><td className="api-quote-update"><DataUpdated at={station.lastUpdatedAt} now={now}/></td><td><ModelAction station={station} price={p}/></td></tr>)}</tbody></table></div>;
}

const PAGE_SIZE=30;
export function Api() {
  const [params,setParams]=useSearchParams();
  const kind=params.get('type')==='official'?'official':'relay';
  const {stations:transitStations,loading,error}=useTransit(kind==='relay');
  const family=apiFamilies.some(f=>f.id===params.get('family'))?params.get('family')??'':params.get('model')==='GPT'?'gpt':'';
  const query=params.get('q')??'';
  const selected=kind==='relay'?transitStations.find(s=>s.id===params.get('station')):undefined;
  const model=params.get('model')??'';
  const view=params.get('view')==='grid'?'grid':'list';
  const sort=params.get('sort')??'';
  const [now,setNow]=useState(Date.now);
  useEffect(()=>{const t=window.setInterval(()=>setNow(Date.now()),60000);return()=>window.clearInterval(t);},[]);
  const stickyRoot=useStickyStack(params.toString());
  const update=(changes:Record<string,string>,replace=false)=>{const next=new URLSearchParams(params);next.delete('page');for(const [key,value] of Object.entries(changes)){value?next.set(key,value):next.delete(key);}setParams(next,{replace});};
  const href=(id:string)=>{const next=new URLSearchParams(params);next.delete('q');next.delete('page');next.set('station',id);return `/api-pricing?${next}`;};
  const back=new URLSearchParams(params);back.delete('station');back.delete('q');back.delete('page');
  const familyPrices=(s:TransitStation)=>s.prices.filter(p=>(!family||p.family===family)&&(!model||model==='GPT'||p.standardModel===model));
  const filtered=useMemo(()=>transitStations.map(station=>({station,prices:familyPrices(station)})).filter(({station,prices})=>prices.length>0&&`${station.name} ${station.summary} ${prices.map(p=>p.standardModel).join(' ')}`.toLowerCase().includes(query.trim().toLowerCase())).sort((a,b)=>sort==='price'?(combinedRate(bestPrice(a.prices))??Infinity)-(combinedRate(bestPrice(b.prices))??Infinity):sort==='models'?new Set(b.prices.map(p=>p.standardModel)).size-new Set(a.prices.map(p=>p.standardModel)).size:0),[transitStations,family,model,query,sort,now]);
  const quotes=selected?familyPrices(selected).filter(p=>`${p.standardModel} ${p.groupName}`.toLowerCase().includes(query.trim().toLowerCase())).sort((a,b)=>sort==='price'?(combinedRate(a)??Infinity)-(combinedRate(b)??Infinity):sort==='stability'?(quoteMonitoring(b)?.rate??-1)-(quoteMonitoring(a)?.rate??-1):0):[];
  const models=[...new Set((selected?selected.prices:transitStations.flatMap(s=>s.prices)).filter(p=>!family||p.family===family).map(p=>p.standardModel).filter((s):s is string=>!!s))].sort();
  const official=apiProviders.filter(p=>p.kind==='official'&&(!family||p.families.includes(family))&&`${p.name} ${p.models}`.toLowerCase().includes(query.toLowerCase()));
  const title=selected?.name??apiFamilies.find(f=>f.id===family)?.label??'全部';
  const count=kind==='relay'&&loading&&!transitStations.length?'正在读取…':kind==='official'?`${official.length} 个官方平台`:selected?`${new Set(quotes.map(p=>p.standardModel)).size} 个模型 · ${quotes.length} 条报价`:`${filtered.length} 家中转站 · ${filtered.reduce((n,s)=>n+s.prices.length,0)} 条报价`;
  const page=Math.max(1,Math.min(Math.ceil(quotes.length/PAGE_SIZE)||1,Number(params.get('page'))||1));
  const visibleQuotes=quotes.slice((page-1)*PAGE_SIZE,page*PAGE_SIZE);
  const pageLink=(target:number)=>{const next=new URLSearchParams(params);next.set('page',String(target));setParams(next);};
  return <div ref={stickyRoot} className="catalog-page api-workspace container page-body">
    <div className="directory-heading directory-search-heading catalog-category-heading">
      <h1>API</h1><div className="category-heading-summary"><div className="category-heading-label">{selected&&<Link className="detail-title-back" to={`/api-pricing?${back}`} aria-label="返回 API 目录"><ChevronLeft size={30}/></Link>}<h2>{title}</h2></div><p>{count}</p></div>
      <SearchField value={query} onChange={q=>update({q},true)} label="搜索模型或服务商" placeholder={selected?'搜索模型或分组…':'搜索模型或服务商…'}/>
    </div>
    <div className="catalog-layout">
      <aside className="catalog-sidebar" aria-label="API 模型分类"><div className="catalog-tabs" role="group" aria-label="API 模型分类">{apiFamilies.filter(f=>kind==='official'||!f.officialOnly).map(f=><button key={f.id} className={family===f.id?'active':''} aria-pressed={family===f.id} onClick={()=>update({family:f.id,model:'',station:'',q:''})}><FamilyLogo id={f.id}/>{f.label}</button>)}</div></aside>
      <div className="catalog-content">
        {selected&&<StationProfile station={selected} now={now}/>}
        <div className="catalog-toolbar api-toolbar">
          <nav className="other-category-tabs" aria-label="API 类型">{selected?<span className="api-section-title">模型报价</span>:<>{[['relay','中转渠道'],['official','官方 API']].map(([id,label])=><button key={id} className={kind===id?'active':''} aria-pressed={kind===id} onClick={()=>update({type:id,family:id==='relay'&&apiFamilies.find(f=>f.id===family)?.officialOnly?'':family,station:'',model:'',q:''})}>{id==='relay'?<Network size={16}/>:<Building2 size={16}/>} {label}</button>)}</>}</nav>
          <div className="toolbar-actions">{kind==='relay'&&<><div className="api-model-select"><GlassSelect aria-label="选择具体模型" value={model==='GPT'?'':model} onChange={model=>update({model})}><option value="">全部模型</option>{models.map(m=><option key={m} value={m}>{m}</option>)}</GlassSelect></div><GlassSelect aria-label="API 排序" value={sort} onChange={sort=>update({sort})}><option value="">默认排序</option><option value="price">综合系数从低到高</option>{selected?<option value="stability">可用性从高到低</option>:<option value="models">模型数量从多到少</option>}</GlassSelect></>}
            <button className="view-switch" type="button" aria-label={view==='list'?'切换为网格':'切换为列表'} onClick={()=>update({view:view==='list'?'grid':'list'})}>{view==='list'?<LayoutGrid size={18}/>:<List size={18}/>}</button>
          </div>
        </div>
        {kind==='relay'&&<p className="api-data-status" role="status">{loading?'正在读取原站报价…':error?`${error}${transitStations.length?'；保留上次完整数据':''}`:'原站约每 15 分钟采集；本页每 5 分钟读取更新。'}{!loading&&transitStations.some(s=>isTransitStale(s,now))?' 部分来源数据待更新，请以原站为准。':''}</p>}
        {kind==='official'?official.length?<div className={view==='grid'?'subscription-grid api-cards':'api-official-list'}>{official.map(p=><article className="api-official-card glass-surface" key={p.id}><span className="api-identity"><ApiLogo name={p.name} src={p.logo}/><span><strong>{p.name}</strong><small>{p.models.join(' · ')}</small></span></span><p>{p.billing}</p><span className="api-official-note">{p.note}</span><div className="api-official-links"><a className="api-site-link" href={p.pricingUrl} target="_blank" rel="noreferrer">官方定价<ChevronRight size={15}/></a><PurchaseLink url={p.url}/></div></article>)}</div>:<EmptyState title="没有对应的官方平台" description="试试其他模型分类或关键词。"/>:selected?quotes.length?<QuoteResults station={selected} prices={visibleQuotes} view={view} now={now}/>:<EmptyState title="没有对应的模型报价" description="试试其他模型或分组关键词。"/>:filtered.length?view==='list'?<div className="catalog-table-wrap api-table-wrap"><table className="catalog-table api-stations-table"><colgroup>{[14,18,18,10,15,15,10].map((w,i)=><col key={i} style={{width:`${w}%`}}/>)}</colgroup><thead><tr>{['中转站','模型 / 报价概况','倍率','缓存命中率','近期可用性','吞吐 / 延迟','操作'].map(t=><th key={t} scope="col">{t}</th>)}</tr></thead><tbody>{filtered.map(({station,prices})=>{const best=bestPrice(prices);const monitor=stationMonitoring(station);return <tr key={station.id}><td><Link to={href(station.id)}><StationIdentity station={station}/></Link><small><DataUpdated at={station.lastUpdatedAt} now={now}/></small></td><td><ModelOverview prices={prices} family={family}/></td><td><DirectoryMetrics prices={prices}/></td><td><CacheSummary station={station} prices={prices}/></td><td><MonitoringSummary monitor={monitor}/></td><td><PerformanceSummary monitor={monitor}/></td><td><Link className="api-site-link" to={href(station.id)}>详情<ChevronRight size={15}/></Link></td></tr>;})}</tbody></table></div>:<div className="subscription-grid api-cards">{filtered.map(({station,prices})=>{const best=bestPrice(prices);const monitor=stationMonitoring(station);return <article key={station.id} className="api-station-card glass-surface"><Link to={href(station.id)}><StationIdentity station={station}/></Link><ModelOverview prices={prices} family={family}/><DirectoryMetrics prices={prices}/><div className="api-card-telemetry"><CacheSummary station={station} prices={prices}/><PerformanceSummary monitor={monitor}/></div><MonitoringSummary monitor={monitor}/><footer><span><DataUpdated at={station.lastUpdatedAt} now={now}/></span><Link className="api-home-link" to={href(station.id)}>详情<ChevronRight size={15}/></Link></footer></article>;})}</div>:<EmptyState title={loading?"正在读取原站报价":error?"API 报价暂时无法加载":"没有匹配的中转站"} description={loading?"正在读取各站最新采集结果，请稍候。":error||"试试其他模型分类或关键词。"}/>}
        {selected&&<Pagination page={page} total={Math.ceil(quotes.length/PAGE_SIZE)} onChange={pageLink} label="模型报价分页"/>}
        {!selected&&kind==='relay'&&<div className="api-explanations"><article className="glass-surface"><h3>倍率怎么看</h3><p>综合系数 = 充值系数 × 原站模型倍率，仅对可核实的人民币充值方案展示。各站基准可能不同，请选定同一模型并核对输入、输出单价；美元额度、阶梯计费和过期报价不参与系数排序。</p></article><article className="glass-surface"><h3>可用性与来源</h3><p>首页展示全站公开监测；未提供全站汇总时，按去重后的公开分组或模型汇总，有样本数则加权，否则标注等权。详情使用对应模型或分组数据。吞吐区分平均生成速度与总 Token 吞吐，延迟区分首字、响应与探测口径。</p></article></div>}
      </div>
    </div>
  </div>;
}
