import {test} from 'node:test';
import assert from 'node:assert/strict';
import {inventory} from '../worker/stock';
import {parse16688,parseShopApi,parseHtml,parseDujiao} from '../worker/collectors';
import {stockDisplay} from '../src/lib/offers';
import type {Source} from '../worker/types';
import type {Offer} from '../src/data/types';
const source={base_url:'https://merchant.example.com',config:{}} as Source;
test('qualitative stock never invents quantity and explicit sold-out wins over stale count',()=>{
 assert.deepEqual(inventory('库存充足').raw_data,{stock_quantity:null,stock_text:'库存充足'});
 assert.equal(inventory('out_of_stock',80).raw_data?.stock_quantity,0);
 assert.equal(inventory(-1).stock_status,'unknown');
 const rows=parse16688([{goods_no:'G1',name:'AI',price:12,stock_available_status:'enough',stock_available_quantity:0}],source);
 assert.equal(rows[0].stock_status,'in_stock');assert.equal(rows[0].raw_data?.stock_quantity,null);assert.equal(rows[0].raw_data?.stock_text,'库存很多');
});
test('shop platform preserves its public qualitative labels instead of disclosing hidden exact counts',()=>{
 const rows=parseShopApi([0,3,18,35].map((n,id)=>({goods_key:id,name:'AI',price:10,extend:{stock_count:n,show_stock_type:0}})),source);
 assert.deepEqual(rows.map(x=>x.raw_data?.stock_text),['缺货','库存少量','库存一般','库存充足']);
 assert.deepEqual(rows.map(x=>x.raw_data?.stock_quantity),[0,null,null,null]);
 assert.equal(parseShopApi([{goods_key:1,name:'AI',price:10,extend:{stock_count:17,show_stock_type:1}}],source)[0].raw_data?.stock_quantity,17);
 assert.equal(parseShopApi([{goods_key:1,name:'Free instructions',price:0}],source).length,0);
});
test('HTML inventory preserves source wording and exact declared quantities',()=>{
 const s={...source,config:{item_selector:'article',title_selector:'h3',price_selector:'b',link_selector:'a',stock_selector:'small',stock_prefix:'库存：'}};
 const rows=parseHtml('<article><h3>AI</h3><b>12</b><a href="/buy/1"></a><small>库存：充足</small></article><article><h3>AI</h3><b>12</b><a href="/buy/2"></a><small>库存：37</small></article>',s);
 assert.equal(rows[0].raw_data?.stock_text,'充足');assert.equal(rows[1].raw_data?.stock_quantity,37);
});
test('stock display distinguishes unknown, qualitative, exact and expired observations',()=>{
 const now=Date.now();const offer={stock_status:'in_stock',expires_at:new Date(now+60000).toISOString()} as Offer;
 assert.equal(stockDisplay({...offer,stock_quantity:3},now),'3 件');
 assert.equal(stockDisplay({...offer,stock_text:'库存充足'},now),'库存充足');
 assert.equal(stockDisplay({...offer,stock_quantity:701,stock_text:'库存很多'},now),'库存很多');
 assert.equal(inventory('即将售罄').stock_status,'in_stock');
 assert.equal(stockDisplay(offer,now),'有货 · 数量未公布');
 assert.equal(stockDisplay({...offer,stock_status:'unknown'},now),'未公布库存');
 assert.equal(stockDisplay({...offer,stock_status:'out_of_stock',stock_quantity:99},now),'缺货');
 assert.equal(stockDisplay({...offer,expires_at:new Date(now-1).toISOString()},now),'库存待更新');
});
test('aggregate parent inventory is never repeated as each SKU quantity',()=>{
 const rows=parseDujiao([{id:1,title:'AI',fulfillment_type:'manual',manual_stock_available:99,stock_status:'in_stock',skus:[{id:1,price_amount:10},{id:2,price_amount:20}]}],source);
 assert.deepEqual(rows.map(x=>x.raw_data?.stock_quantity),[null,null]);
 assert.deepEqual(rows.map(x=>x.stock_status),['unknown','unknown']);
});
test('a sold-out cheap SKU does not inherit availability from other stocked variants',()=>{
 const rows=parseDujiao([{id:15,title:'GPT UPI提链',slug:'ChatGPT-UPI',fulfillment_type:'auto',auto_stock_available:39,stock_status:'in_stock',is_sold_out:false,skus:[
  {id:36,price_amount:3,auto_stock_available:0,upstream_stock:0,stock_status:'in_stock'},
  {id:37,price_amount:12,auto_stock_available:29,upstream_stock:0},
  {id:38,price_amount:45,auto_stock_available:10,upstream_stock:0},
 ]}],source);
 assert.deepEqual(rows.map(x=>x.stock_status),['out_of_stock','in_stock','in_stock']);
 assert.deepEqual(rows.map(x=>x.raw_data?.stock_quantity),[0,29,10]);
 assert.equal(Math.min(...rows.filter(x=>x.stock_status==='in_stock').map(x=>x.price)),12);
 const manual=parseDujiao([{id:1,title:'AI',fulfillment_type:'manual',stock_status:'in_stock',skus:[{id:1,price_amount:2,manual_stock_total:8,manual_stock_sold:8},{id:2,price_amount:3,manual_stock_total:8,manual_stock_sold:3}]}],source);
 assert.deepEqual(manual.map(x=>x.stock_status),['out_of_stock','in_stock']);
});
