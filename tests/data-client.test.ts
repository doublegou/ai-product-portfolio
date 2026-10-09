import test from "node:test";
import assert from "node:assert/strict";
import { loadOffers } from "../src/data/client";
import { readSources } from "../scripts/shared";
import worker from "../worker/index";
import type { Env } from "../worker/types";

const offer = { id: "a", raw_title: "ChatGPT Plus 代充 30天", platform: "ChatGPT", plan: "Plus", delivery: "代充", duration_days: 30,
  comparison_key: "plus-30", review_required: false, price: 120, currency: "CNY", stock_status: "in_stock", purchase_url: "https://shop.example.com/1",
  last_seen_at: "2026-10-08T00:00:00Z", expires_at: "2026-10-09T00:00:00Z", sources: { name: "原站", base_url: "https://shop.example.com/" } };

test("source registry identifies original shops, including multiple shops on one host", () => {
  const rows = readSources();
  assert.ok(rows.length > 0);
  assert.equal(new Set(rows.map(row => row.base_url)).size, rows.length);
  assert.ok(rows.filter(row => row.base_url.includes("16688.com.cn/shop/")).length > 1);
});

test("unconfigured deployment serves the UI and returns a clear API status", async () => {
  const env = { ASSETS: { fetch: async () => new Response("site") } } as unknown as Env;
  assert.equal((await worker.fetch(new Request("https://app.example.com/"), env)).status, 200);
  assert.equal((await worker.fetch(new Request("https://app.example.com/api/offers"), env)).status, 410);
});
