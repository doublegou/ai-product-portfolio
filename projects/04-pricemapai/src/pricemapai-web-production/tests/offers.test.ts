import { test } from "node:test";
import assert from "node:assert/strict";
import { demo, capturedAt } from "../src/data/demo";
import {
  classifyProduct,
  lowestIds,
  summarize,
  safeLink,
  stockLabel,
} from "../src/lib/offers";
import type { Offer } from "../src/data/types";

const now = Date.parse(capturedAt);
const base = demo.offers[0];
const offer = (
  id: string,
  price: number,
  changes: Partial<Offer> = {},
): Offer => ({
  ...base,
  id,
  price,
  sources: { name: id, base_url: `https://${id}.example.com/` },
  ...changes,
});

test("lowest prices never mix currencies, duration or delivery, even with a reused comparison key", () => {
  const rows = [
    offer("a", 100),
    offer("b", 120),
    offer("usd", 2, { currency: "USD" }),
    offer("year", 50, { duration_days: 365 }),
    offer("shared", 10, { delivery: "共享" }),
  ];
  assert.deepEqual([...lowestIds(rows, now)], ["a"]);
});

test("stale, unknown-stock, sold-out and unverified offers cannot win a lowest-price label", () => {
  const rows = [
    offer("a", 100),
    offer("b", 120),
    offer("stale", 1, { expires_at: new Date(now - 1).toISOString() }),
    offer("unknown", 1, { stock_status: "unknown" }),
    offer("sold", 1, { stock_status: "out_of_stock" }),
    offer("review", 1, { review_required: true }),
    offer("unkeyed", 1, { comparison_key: null }),
  ];
  assert.deepEqual([...lowestIds(rows, now)], ["a"]);
});

test("ties are retained and at least two distinct shops are needed", () => {
  assert.deepEqual(
    [...lowestIds([offer("a", 100), offer("b", 100)], now)],
    ["a", "b"],
  );
  assert.equal(
    lowestIds(
      [
        offer("a", 100),
        offer("b", 80, {
          sources: { name: "a", base_url: "https://a.example.com/" },
        }),
      ],
      now,
    ).size,
    0,
  );
});

test("accessories, trials and ambiguous multiplier plans remain separate from normal subscriptions", () => {
  assert.equal(
    classifyProduct({ ...base, raw_title: "ChatGPT Plus 试用账号 3天" }),
    "unclassified",
  );
  assert.equal(
    classifyProduct({ ...base, raw_title: "ChatGPT 接码服务" }),
    "verification",
  );
  assert.equal(
    classifyProduct({ ...base, plan: "未知", raw_title: "Gmail 邮箱账号" }),
    "email",
  );
  assert.equal(
    classifyProduct({ ...base, raw_title: "ChatGPT Plus 代充到邮箱" }),
    "chatgpt-plus",
  );
  assert.equal(
    classifyProduct({
      ...base,
      platform: "Claude",
      plan: "Max",
      raw_title: "Claude Max 月卡",
    }),
    "unclassified",
  );
  assert.equal(
    classifyProduct({
      ...base,
      platform: "Claude",
      plan: "Max",
      raw_title: "Claude Max 20× 月卡",
    }),
    "claude-max-20",
  );
  assert.equal(
    classifyProduct({
      ...base,
      platform: "Claude",
      plan: "Max",
      raw_title: "Claude Max 5x 月卡",
    }),
    "claude-max-5",
  );
});

test("summaries count distinct shop URLs, use one currency and exclude stale reference prices", () => {
  const rows = [
    offer("a", 100),
    offer("b", 150),
    offer("c", 1, { currency: "USD" }),
    offer("d", 0.5, { expires_at: new Date(now - 1).toISOString() }),
  ];
  const [product] = summarize(rows, now);
  assert.equal(product.referencePrice, 100);
  assert.equal(product.channels, 4);
  assert.equal(product.available, 3);
  assert.equal(summarize(rows, now, "USD")[0].referencePrice, 1);
});

test("all sold-out quotes display no reference price, never zero or Infinity", () => {
  const [product] = summarize(
    [offer("a", 80, { stock_status: "out_of_stock" })],
    now,
  );
  assert.equal(product.referencePrice, null);
  assert.equal(product.available, 0);
  assert.equal(
    stockLabel({ ...base, stock_status: "unknown" }, now),
    "库存待确认",
  );
});

test("the demo covers 13 subscription products, accessories, and unclassified quotes with unique IDs", () => {
  assert.equal(new Set(demo.offers.map((o) => o.id)).size, demo.offers.length);
  const summaries = summarize(demo.offers, now);
  assert.equal(
    summaries.filter((p) => p.category === "subscription").length,
    13,
  );
  assert.equal(summaries.filter((p) => p.category === "accessory").length, 2);
  assert.equal(
    summaries.find((p) => p.id === "unclassified")?.offers.length,
    8,
  );
});

test("merchant links reject executable, malformed and embedded-credential URLs", () => {
  for (const url of [
    "javascript:alert(1)",
    "data:text/html,test",
    "not a URL",
    "https://user:secret@example.com/",
  ])
    assert.equal(safeLink(url), undefined);
  assert.equal(safeLink("https://gospv.com/"), "https://gospv.com/");
});
