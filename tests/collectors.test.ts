import { test } from "node:test";
import assert from "node:assert/strict";
import { classify } from "../worker/classify";
import {
  parseKami,
  parseDujiao,
  parseHtml,
  money,
  collect,
} from "../worker/collectors";
import { safeUrl } from "../worker/network";
import type { Source } from "../worker/types";
const source = {
  id: "x",
  name: "Test",
  base_url: "https://merchant.example.com/",
  collector: "kami",
  config: {},
  interval_minutes: 60,
  enabled: true,
  lease_token: "x",
  last_success_at: null,
  last_error: null,
  next_crawl_at: "",
} satisfies Source;
test("delivery and duration keep unlike subscriptions out of the same comparison", () => {
  const a = classify("ChatGPT Plus 代充 1个月"),
    b = classify("ChatGPT Plus 成品账号 1个月"),
    c = classify("ChatGPT Plus 代充 1年");
  assert.notEqual(a.comparison_key, b.comparison_key);
  assert.notEqual(a.comparison_key, c.comparison_key);
  assert.equal(a.review_required, false);
  assert.equal(classify("ChatGPT Plus 试用账号 3天").comparison_key, null);
  assert.equal(classify("Claude Max 20倍 1个月代充").comparison_key, null);
});
test("unknown inventory is preserved and hidden products do not count as in stock", () => {
  const rows = parseKami(
    [
      { id: 1, name: "Claude Pro 1个月代充", user_price: "125.50" },
      { id: 2, name: "Hidden", price: 9, stock: 99, hide: 1 },
    ],
    source,
  );
  assert.equal(rows[0].stock_status, "unknown");
  assert.equal(rows[1].stock_status, "out_of_stock");
  assert.equal(rows[0].price, 125.5);
});
test("Kami storefronts retain their configured purchase route on every collection", () => {
  const item = { id: 11, name: "Grok 普号", price: 0.08, stock: 2354 };
  assert.equal(parseKami([item], source)[0].purchase_url, 'https://merchant.example.com/commodity?id=11');
  const storefront = { ...source, base_url: 'https://store.codesky.qzz.io', config: { purchase_path: '/item/{id}' } };
  assert.equal(parseKami([item], storefront)[0].purchase_url, 'https://store.codesky.qzz.io/item/11');
  assert.equal(parseKami([{ ...item, id: 'a/b' }], storefront)[0].purchase_url, 'https://store.codesky.qzz.io/item/a%2Fb');
});
test("each SKU keeps its own price and stock", () => {
  const rows = parseDujiao(
    [
      {
        id: 9,
        title: "ChatGPT Plus 代充",
        slug: "plus",
        skus: [
          { id: 1, title: "1个月", price_amount: 100, auto_stock_available: 3 },
          { id: 2, title: "1年", price_amount: 1000, is_sold_out: true },
        ],
      },
    ],
    source,
  );
  assert.equal(rows.length, 2);
  assert.notEqual(rows[0].external_id, rows[1].external_id);
  assert.equal(rows[1].stock_status, "out_of_stock");
  assert.equal(rows[1].price, 1000);
});
test("HTML selectors extract the current price without accidentally reading strike-through prices", () => {
  const s = {
    ...source,
    collector: "html" as const,
    config: {
      item_selector: ".product",
      title_selector: "h2",
      price_selector: ".current",
      link_selector: "a",
    },
  };
  const rows = parseHtml(
    '<div class="product"><h2>Claude Pro 代充 1个月</h2><del>¥200</del><b class="current">¥125.00</b><a href="/buy/1">购买</a></div>',
    s,
  );
  assert.equal(rows[0].price, 125);
  assert.equal(rows[0].purchase_url, "https://merchant.example.com/buy/1");
});
test("invalid and private source addresses or zero prices are rejected", () => {
  for (const url of [
    "http://example.com",
    "https://127.0.0.1",
    "https://[::1]",
    "https://foo.local",
    "https://user:secret@example.com",
    "https://example.com:8080",
  ])
    assert.throws(() => safeUrl(url));
  for (const p of ["free", 0, -1, Infinity]) assert.throws(() => money(p));
});
test("empty API results cause a failed crawl instead of removing previous offers", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url) =>
    String(url).endsWith("robots.txt")
      ? new Response("", { status: 404 })
      : Response.json({ data: [] });
  try {
    await assert.rejects(() => collect(source), /商品列表为空/);
  } finally {
    globalThis.fetch = original;
  }
});
test("robots denial prevents requesting the product API", async () => {
  const original = globalThis.fetch;
  let count = 0;
  globalThis.fetch = async () => {
    count++;
    return new Response("User-agent: *\nDisallow: /user/");
  };
  try {
    await assert.rejects(() => collect(source), /robots.txt/);
    assert.equal(count, 1);
  } finally {
    globalThis.fetch = original;
  }
});
test("truncated pagination never claims to be a complete snapshot", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url) =>
    String(url).endsWith("robots.txt")
      ? new Response("", { status: 404 })
      : Response.json({
          data: Array.from({ length: 100 }, (_, id) => ({
            id: String(url) + "-" + id,
            name: "ChatGPT Plus 1个月代充",
            price: 100,
            stock: 2,
          })),
        });
  try {
    const result = await collect(source);
    assert.equal(result.offers.length, 300);
    assert.equal(result.complete, false);
  } finally {
    globalThis.fetch = original;
  }
});

test("stock status wins over auto inventory for manually delivered SKUs and inactive SKUs are skipped", () => {
  const rows = parseDujiao(
    [
      {
        id: 1,
        title: "Claude Pro 代充",
        fulfillment_type: "manual",
        skus: [
          {
            id: 1,
            price_amount: 100,
            auto_stock_available: 0,
            stock_status: "in_stock",
            spec_values: { term: "1个月" },
          },
          { id: 2, price_amount: 200, is_active: false },
        ],
      },
    ],
    source,
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].stock_status, "in_stock");
  assert.match(rows[0].raw_title, /1个月/);
  assert.equal(classify("ChatGPT Plus 个人账号代充 1个月").delivery, "代充");
});

test("upgrade mentions never replace the primary plan and region/usage restrictions require review", () => {
  const c = classify(
    "ChatGPT 1个月Pro 100 (5X)官方订阅【支持plus升级，可返0-100元】",
  );
  assert.equal(c.plan, "Pro");
  assert.equal(c.comparison_key, null);
  assert.equal(classify("Claude Max5X 1个月代充").plan, "Max");
  assert.equal(
    classify("ChatGPT Plus 1个月卡付订阅 到期后充值").review_required,
    true,
  );
});

test("16688 isolates the shop ID and preserves original price, inventory and fee notice", async () => {
  const original = globalThis.fetch;
  const bodies: any[] = [];
  globalThis.fetch = async (url, init) => {
    if (String(url).endsWith("robots.txt"))
      return new Response("", { status: 404 });
    bodies.push(JSON.parse(String(init?.body)));
    return Response.json({
      code: 1,
      data: {
        list: [
          {
            goods_no: "G12345",
            name: "ChatGPT Plus 30天直充",
            price: 108.99,
            stock_available_quantity: 0,
          },
        ],
      },
    });
  };
  try {
    const result = await collect({
      ...source,
      collector: "16688",
      base_url: "https://www.16688.com.cn/shop/S123456",
    });
    assert.equal(bodies[0].shop_no, "S123456");
    assert.equal(result.complete, true);
    assert.equal(result.offers[0].price, 108.99);
    assert.equal(result.offers[0].stock_status, "out_of_stock");
    assert.match(String(result.offers[0].raw_data?.price_note), /手续费/);
    assert.equal(
      result.offers[0].purchase_url,
      "https://www.16688.com.cn/goods/G12345",
    );
    await assert.rejects(
      () =>
        collect({
          ...source,
          collector: "16688",
          base_url: "https://www.16688.com.cn/",
        }),
      /完整/,
    );
  } finally {
    globalThis.fetch = original;
  }
});
test("16688 failures and free items never erase a prior snapshot", async () => {
  const original = globalThis.fetch;
  for (const payload of [
    { code: 0, data: { list: [] } },
    { code: 1, data: { list: [] } },
    { code: 1, data: { list: [{ goods_no: "G123", name: "demo", price: 0 }] } },
  ]) {
    globalThis.fetch = async (url) =>
      String(url).endsWith("robots.txt")
        ? new Response("", { status: 404 })
        : Response.json(payload);
    try {
      await assert.rejects(() =>
        collect({
          ...source,
          collector: "16688",
          base_url: "https://www.16688.com.cn/shop/S123",
        }),
      );
    } finally {
      globalThis.fetch = original;
    }
  }
});
test("ancillary goods cannot compete with subscriptions even when their title includes a plan", () => {
  for (const title of [
    "Gemini Pro 1个月代充资格号",
    "Grok Pro 1个月CDK邀请码",
    "Gemini Pro 30天虚拟卡",
    "ChatGPT Plus 30天接码充值",
  ]) {
    const result = classify(title);
    assert.equal(result.comparison_key, null);
    assert.equal(result.plan, "未知");
    assert.equal(result.review_required, true);
  }
  assert.equal(classify("GP.T Plus 30天直充").platform, "ChatGPT");
  assert.equal(classify("G·P·T Go 1个月直充").platform, "ChatGPT");
});

test('Dujiao respects server pagination even when a page is shorter than the requested limit',async()=>{
 const original=globalThis.fetch;const pages:number[]=[];
 globalThis.fetch=async(url)=>{
  if(String(url).endsWith('robots.txt'))return new Response('',{status:404});
  const page=Number(new URL(String(url)).searchParams.get('page'));pages.push(page);
  return Response.json({data:[{id:page,title:'AI',price_amount:20,auto_stock_available:1}],pagination:{page,total_page:2,page_size:1,total:2}});
 };
 try{const result=await collect({...source,collector:'dujiao',base_url:'https://dujiao.example.com'});assert.deepEqual(pages,[1,2]);assert.equal(result.offers.length,2);assert.equal(result.complete,true);}finally{globalThis.fetch=original;}
});

test('ShopApi reads all four original storefront tabs and skips free instructions',async()=>{
 const original=globalThis.fetch;const tabs:string[]=[];
 globalThis.fetch=async(url,init)=>{
  if(String(url).endsWith('robots.txt'))return new Response('',{status:404});
  const body=JSON.parse(String(init?.body));tabs.push(body.goods_type);assert.equal(body.category_id,0);
  return Response.json({code:1,data:{total:2,list:[{goods_key:body.goods_type,name:'AI',price:20,extend:{stock_count:20,show_stock_type:0}},{goods_key:'free',name:'教程',price:0}]}});
 };
 try{const result=await collect({...source,collector:'shopapi',base_url:'https://shopapi.example.com/shop/x',config:{shop_token:'x'}});assert.deepEqual(tabs,['card','equity','resource','article']);assert.equal(result.offers.length,4);assert.equal(result.complete,true);}finally{globalThis.fetch=original;}
});
