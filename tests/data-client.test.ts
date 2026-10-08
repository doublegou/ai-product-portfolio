import test from "node:test";
import assert from "node:assert/strict";
import { loadOffers } from "../src/data/client";
import { readSources } from "../scripts/shared";
import worker from "../worker/index";
import type { Env } from "../worker/types";

const offer = { id: "a", raw_title: "ChatGPT Plus 代充 30天", platform: "ChatGPT", plan: "Plus", delivery: "代充", duration_days: 30,
  comparison_key: "plus-30", review_required: false, price: 120, currency: "CNY", stock_status: "in_stock", purchase_url: "https://shop.example.com/1",
  last_seen_at: "2026-10-08T00:00:00Z", expires_at: "2026-10-09T00:00:00Z", sources: { name: "原站", base_url: "https://shop.example.com/" } };

test("live offers follow pagination and deduplicate repeated IDs", async () => {
  const calls: string[] = [];
  const rows = await loadOffers((async (url: string) => {
    calls.push(url);
    return Response.json(calls.length === 1 ? { offers: [offer], next_offset: 1 } : { offers: [offer, { ...offer, id: "b" }], next_offset: null });
  }) as typeof fetch);
  assert.equal(rows.length, 2);
  assert.match(calls[1], /offset=1$/);
});

test("partial failures and invalid cursors never resolve as a complete dataset", async () => {
  let calls = 0;
  await assert.rejects(loadOffers((async () => ++calls === 1 ? Response.json({ offers: [offer], next_offset: 1 }) : new Response("unavailable", { status: 503 })) as typeof fetch), /尚未连接/);
  await assert.rejects(loadOffers((async () => Response.json({ offers: [offer], next_offset: 0 })) as typeof fetch), /分页/);
  await assert.rejects(loadOffers((async () => Response.json({ offers: [{ ...offer, price: null }], next_offset: null })) as typeof fetch), /格式/);
  await assert.rejects(loadOffers((async () => Response.json({ offers: [offer] })) as typeof fetch), /分页/);
});

test("empty live dataset remains empty instead of substituting sample prices", async () => {
  assert.deepEqual(await loadOffers((async () => Response.json({ offers: [], next_offset: null })) as typeof fetch), []);
});

test("source registry identifies original shops, including multiple shops on one host", () => {
  const rows = readSources();
  assert.ok(rows.length > 0);
  assert.equal(new Set(rows.map(row => row.base_url)).size, rows.length);
  assert.ok(rows.filter(row => row.base_url.includes("16688.com.cn/shop/")).length > 1);
});

test("unconfigured deployment serves the UI and returns a clear API status", async () => {
  const env = { ASSETS: { fetch: async () => new Response("site") } } as unknown as Env;
  assert.equal((await worker.fetch(new Request("https://app.example.com/"), env)).status, 200);
  assert.equal((await worker.fetch(new Request("https://app.example.com/api/offers"), env)).status, 503);
});
