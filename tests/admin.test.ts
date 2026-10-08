import test from "node:test";
import assert from "node:assert/strict";
import worker from "../worker/index";
import type { Env } from "../worker/types";
import { parseHtml, parseKami } from "../worker/collectors";
import { classify } from "../worker/classify";
const env = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "test-only",
  ADMIN_TOKEN: "test-admin",
  ASSETS: {
    fetch: async (req: Request) =>
      new Response(new URL(req.url).pathname, {
        headers: { "Cache-Control": "public,max-age=3600" },
      }),
  },
} as unknown as Env;

test("admin route serves the separate document with no indexing or caching", async () => {
  for (const path of ["/admin", "/admin/", "/admin.html"]) {
    const r = await worker.fetch(
      new Request("https://app.example.com" + path),
      env,
    );
    assert.equal(await r.text(), "/admin");
    assert.equal(r.headers.get("Cache-Control"), "no-store");
    assert.equal(r.headers.get("X-Robots-Tag"), "noindex, nofollow");
  }
  const publicPage = await worker.fetch(
    new Request("https://app.example.com/"),
    env,
  );
  assert.equal(await publicPage.text(), "/");
});

test("every management route requires the admin key, including preview", async () => {
  for (const [path, method] of [
    ["sources", "GET"],
    ["runs", "GET"],
    ["preview", "POST"],
    ["crawl", "POST"],
  ] as const) {
    const r = await worker.fetch(
      new Request("https://app.example.com/api/admin/" + path, { method }),
      env,
    );
    assert.equal(r.status, 401);
  }
});

test("preview only calls robots and the source, without writing to Supabase", async () => {
  const original = globalThis.fetch;
  const calls: string[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const url = String(input);
    calls.push(url);
    if (url === "https://shop.example.com/robots.txt")
      return new Response("", { status: 404 });
    if (url === "https://shop.example.com/products")
      return Response.json({
        data: [
          {
            id: 1,
            name: "ChatGPT Plus 代充 30天",
            price: 120,
            stock: 2,
            url: "https://shop.example.com/buy/1",
          },
        ],
      });
    throw Error("Unexpected network call: " + url);
  }) as typeof fetch;
  try {
    const r = await worker.fetch(
      new Request("https://app.example.com/api/admin/preview", {
        method: "POST",
        headers: {
          Authorization: "Bearer test-admin",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: "测试商家",
          base_url: "https://shop.example.com/",
          collector: "json",
          config: { path: "/products", full_snapshot: true },
        }),
      }),
      env,
    );
    assert.equal(r.status, 200);
    const data: any = await r.json();
    assert.equal(data.count, 1);
    assert.equal(data.complete, true);
    assert.equal(data.offers[0].price, 120);
    assert.equal(data.offers[0].platform, "ChatGPT");
    assert.deepEqual(calls, [
      "https://shop.example.com/robots.txt",
      "https://shop.example.com/products",
    ]);
  } finally {
    globalThis.fetch = original;
  }
});

test("HTML stock mapping uses exact source labels and leaves unknown labels unconfirmed", () => {
  const source: any = {
    base_url: "https://shop.example.com/",
    config: {
      item_selector: "a",
      title_selector: "h3",
      price_selector: "strong",
      link_selector: "a",
      stock_selector: "p",
      stock_map: {
        "自动发货·库存 一般": "in_stock",
        "缺货·库存 无货": "out_of_stock",
      },
    },
  };
  const rows = parseHtml(
    '<a href="/1"><h3>ChatGPT Plus</h3><strong>¥120</strong><p>自动发货·库存 一般</p></a><a href="/2"><h3>Claude Pro</h3><strong>¥130</strong><p>缺货·库存 无货</p></a><a href="/3"><h3>Gemini Pro</h3><strong>¥10</strong><p>稍后补货</p></a>',
    source,
  );
  assert.deepEqual(
    rows.map((r) => r.stock_status),
    ["in_stock", "out_of_stock", "unknown"],
  );
});

test("regional prices are not compared as unrestricted subscriptions", () => {
  for (const title of [
    "ChatGPT Plus 菲区代充 1个月",
    "ChatGPT Plus 菲區代充 1个月",
    "ChatGPT Plus 菲律宾代充 1个月",
  ]) {
    assert.equal(classify(title).comparison_key, null);
    assert.equal(classify(title).review_required, true);
  }
});

test("Kami titles display text rather than HTML markup", () => {
  const rows = parseKami(
    [{ id: 1, name: "ChatGPT Plus<br/>自助充值", price: 120, stock: 1 }],
    { base_url: "https://shop.example.com/" } as any,
  );
  assert.equal(rows[0].raw_title, "ChatGPT Plus自助充值");
});

test("HTML inventory prefixes read explicit counts and leave unrelated status text unknown", () => {
  const source: any = {
    base_url: "https://shop.example.com/",
    config: {
      item_selector: ".card",
      title_selector: "h3",
      price_selector: "strong",
      link_selector: "a",
      stock_selector: "small",
      stock_prefix: "库存：",
    },
  };
  const rows = parseHtml(
    '<div class="card"><h3>GPT</h3><strong>120</strong><small>库存：0</small><a href="/buy/1">购买</a></div><div class="card"><h3>Claude</h3><strong>130</strong><small>库存：12</small><a href="/buy/2">购买</a></div><div class="card"><h3>Gemini</h3><strong>10</strong><small>库存待确认</small><a href="/buy/3">购买</a></div>',
    source,
  );
  assert.deepEqual(
    rows.map((r) => r.stock_status),
    ["out_of_stock", "in_stock", "unknown"],
  );
});

test("public offer pagination returns stable ranges and total, rejects invalid bounds", async () => {
  const original = globalThis.fetch;
  let requested = "";
  globalThis.fetch = async (url) => {
    requested = String(url);
    return new Response(JSON.stringify([{ id: "a" }]), {
      headers: {
        "Content-Type": "application/json",
        "Content-Range": "1000-1000/1001",
      },
    });
  };
  try {
    const r = await worker.fetch(
      new Request("https://app.example.com/api/offers?offset=1000&limit=1000"),
      env,
    );
    const result = (await r.json()) as any;
    assert.equal(result.total, 1001);
    assert.equal(result.next_offset, null);
    assert.match(requested, /offset=1000/);
    assert.match(requested, /order=id/);
    for (const q of ["offset=-1", "limit=1001", "offset=NaN", "limit=0"]) {
      assert.equal(
        (
          await worker.fetch(
            new Request("https://app.example.com/api/offers?" + q),
            env,
          )
        ).status,
        400,
      );
    }
  } finally {
    globalThis.fetch = original;
  }
});

test("preview excludes storefront prices with unconfirmed fees from lowest-price comparison", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url) =>
    String(url).endsWith("robots.txt")
      ? new Response("", { status: 404 })
      : Response.json({
          code: 1,
          data: {
            list: [
              {
                goods_no: "G123",
                name: "ChatGPT Plus 30天直充",
                price: 100,
                stock_available_quantity: 2,
              },
            ],
          },
        });
  try {
    const response = await worker.fetch(
      new Request("https://app.example.com/api/admin/preview", {
        method: "POST",
        headers: {
          Authorization: "Bearer test-admin",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: "Original shop",
          base_url: "https://www.16688.com.cn/shop/S123",
          collector: "16688",
        }),
      }),
      env,
    );
    const body = (await response.json()) as any;
    assert.equal(response.status, 200);
    assert.equal(body.offers[0].comparison_key, null);
    assert.equal(body.offers[0].review_required, true);
  } finally {
    globalThis.fetch = original;
  }
});
