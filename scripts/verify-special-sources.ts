import{readFileSync,writeFileSync}from'node:fs';
import{collect}from'../worker/collectors';
import type{Source}from'../worker/types';
const path='artifacts/source-verification.json',report=JSON.parse(readFileSync(path,'utf8'));
const options:any[]=[
 {url:'https://gpt.ybkjs.top',collector:'html',config:{item_selector:'div.flex.flex-1.flex-col:has(h3)',title_selector:'h3',price_selector:'span.text-xl',link_selector:'a[href^="/product/"]',stock_selector:'span:contains("库存")',stock_prefix:'库存',full_snapshot:true}},
 {url:'https://xingbao-ai.shop',collector:'html',config:{item_selector:'article.stitch-product-card',title_selector:'h3',price_selector:'.stitch-price-block strong',link_selector:'.stitch-detail-button',stock_selector:'.stitch-stock-badge:not(.is-sold)',stock_map:{'库存充足':'in_stock','还有少量':'in_stock','暂时缺货':'out_of_stock'},full_snapshot:true,price_note:'商品标价；原站说明部分支付方式另收通道费'}},
 {url:'https://xxxyan.cc',collector:'dujiao',config:{}}
];
for(const option of options){let row=report.results.find((r:any)=>r.reference.url===option.url);const source={name:row.reference.name,base_url:option.url,collector:option.collector,config:option.config,interval_minutes:15};try{const result=await collect(source as Source);Object.assign(row,{status:'verified',source,offer_count:result.offers.length,complete:result.complete,detail:'已按原站页面/接口完成映射'});console.log(option.url,result.offers.length);}catch(e){row.status='failed';row.detail=e instanceof Error?e.message:String(e);console.log(option.url,row.detail);}}
const cat=report.results.find((r:any)=>r.reference.url==='https://catcard.uk');cat.status='failed';cat.detail='原站商品 API 返回 Cloudflare 验证页，未绕过访问限制';
const moved=report.results.find((r:any)=>r.reference.url==='https://19cm.tech');moved.status='moved';moved.detail='原站公告已迁移至 https://geminipro.vip，需核验新站商品接口';
report.checked_at=new Date().toISOString();writeFileSync(path,JSON.stringify(report,null,2));
const p='config/verified-sources.json',rows=JSON.parse(readFileSync(p,'utf8'));for(const row of report.results.filter((r:any)=>r.status==='verified'))if(!rows.some((x:any)=>x.base_url.replace(/\/$/,'')===row.source.base_url))rows.push(row.source);writeFileSync(p,JSON.stringify(rows,null,2)+'\n');console.log({registered:rows.length});
