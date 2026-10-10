import { test } from "node:test";
import assert from "node:assert/strict";
import { products } from "../src/data/products";
import { catalogTabs, productCategory, selectedCategory, selectCategory } from "../src/lib/catalog";

test("every product belongs to one visible category, with mail and verification under other", () => {
  for (const product of products) {
    assert.ok(catalogTabs.some(tab => tab.id === productCategory(product)));
  }
  assert.equal(productCategory(products.find(p => p.id === "email")!), "other");
  assert.equal(productCategory(products.find(p => p.id === "verification")!), "other");
  assert.equal(productCategory(products.find(p => p.id === "unclassified")!), "other");
});

test("switching category removes incompatible legacy filters and resets pagination", () => {
  const old = new URLSearchParams("category=subscription&platform=ChatGPT&page=2&saved=1&q=test");
  const email = selectCategory(old, "email");
  assert.equal(selectedCategory(email), "other");
  assert.equal(email.has("platform"), false);
  assert.equal(email.has("page"), false);
  assert.equal(email.has("saved"), false);
  assert.equal(email.get("q"), "test");
  const platform = selectCategory(email, "Claude");
  assert.equal(platform.has("category"), false);
  assert.equal(selectedCategory(platform), "Claude");
  const all = selectCategory(platform, "");
  assert.equal(selectedCategory(all), "");
  assert.equal(all.has("platform"), false);
});

test("existing platform links still work and old default category means all", () => {
  assert.equal(selectedCategory(new URLSearchParams("platform=ChatGPT")), "ChatGPT");
  assert.equal(selectedCategory(new URLSearchParams("category=subscription")), "");
  assert.equal(selectedCategory(new URLSearchParams("category=unclassified")), "other");
  assert.equal(selectedCategory(new URLSearchParams("category=email")), "other");
  assert.equal(selectedCategory(new URLSearchParams("category=verification")), "other");
});


import { catalogEntries, catalogProducts, catalogProductId, summarizeCatalogEntry } from "../src/lib/catalog";
import { demo, capturedAt } from "../src/data/demo";
import type { Offer } from "../src/data/types";

const classify = (platform: string, title: string, fields: Partial<Offer> = {}) => catalogProductId({
  ...demo.offers[0], platform, plan: "", delivery: "未知", raw_title: title, ...fields,
});

test("catalog prefers fresh prices and labels expired non-sold-out prices as historical", () => {
  const now = Date.parse(capturedAt);
  const row = (id: string, price: number, stock_status: string, extra: Partial<Offer> = {}): Offer => ({
    ...demo.offers[0], id, price, stock_status, currency: "CNY",
    expires_at: new Date(now + 60000).toISOString(), ...extra,
  });
  const product = catalogProducts[0];
  const unknown = row("unknown", 20, "unknown");
  const confirmed = row("confirmed", 100, "in_stock");
  const excluded = [row("sold", 1, "out_of_stock"), row("expired", 2, "unknown", {expires_at: capturedAt}), row("usd", 3, "unknown", {currency: "USD"})];
  const lowest = summarizeCatalogEntry(product, [unknown, confirmed, ...excluded], now);
  assert.equal(lowest.referencePrice, 100);
  assert.equal(lowest.priceKind, "lowest");
  assert.equal(lowest.priceOffer?.id, "confirmed");
  const reference = summarizeCatalogEntry(product, [unknown, ...excluded], now);
  assert.equal(reference.referencePrice, 20);
  assert.equal(reference.priceKind, "reference");
  assert.equal(reference.priceOffer?.id, "unknown");
  assert.equal(reference.available, 0);
  const missing = summarizeCatalogEntry(product, excluded, now);
  assert.equal(missing.referencePrice, 2);
  assert.equal(missing.priceKind, "stale");
  assert.equal(missing.priceOffer?.id, 'expired');
});

test("fixed reference taxonomy includes all categories independently of quote availability", () => {
  const entries = catalogEntries(demo.offers, Date.parse(capturedAt));
  assert.equal(entries.length, 50);
  assert.equal(new Set(entries.map(entry => entry.key)).size, 50);
  assert.deepEqual(entries.filter(entry => entry.platform === "ChatGPT").map(entry => entry.id), [
    "chatgpt-codex-service", "chatgpt-free-account", "chatgpt-plus", "chatgpt-team-business",
    "chatgpt-go", "chatgpt-codex-credits", "chatgpt-plus-recharge", "chatgpt-pro-20x", "chatgpt-pro-5x", "chatgpt-pro-500",
  ]);
  for (const [platform, count] of [["Claude", 7], ["Gemini", 4], ["Grok", 4], ["邮箱", 5], ["接码", 5]] as const) {
    assert.equal(entries.filter(entry => entry.platform === platform).length, count);
  }
  assert.ok(entries.some(entry => entry.offers.length === 0));
  assert.equal(catalogEntries([], Date.parse(capturedAt)).length, 50);
  for (const product of catalogProducts) assert.ok(catalogTabs.some(tab => tab.id === productCategory(product)));
});

test("terms merge into business categories; reference prices do not mix currencies", () => {
  const entries = catalogEntries(demo.offers, Date.parse(capturedAt));
  const recharge = entries.find(entry => entry.id === "chatgpt-plus-recharge")!;
  assert.ok(recharge.offers.some(offer => offer.duration_days === 365));
  assert.ok(recharge.offers.some(offer => offer.duration_days === 30));
  assert.equal(recharge.referencePrice, 108);
  assert.equal(entries.flatMap(entry => entry.offers).length, demo.offers.filter(offer => offer.currency === "CNY").length);
  assert.ok(entries.flatMap(entry => entry.offers).every(offer => offer.currency === "CNY"));
});

test("Plus accounts include trials, disposable accounts and terms; recharge is separate", () => {
  for (const title of ["Plus 日抛成品号", "Plus 次抛", "Plus 试用账号", "Plus 网页号", "Plus 年卡成品号"]) {
    assert.equal(classify("ChatGPT", title), "chatgpt-plus");
  }
  assert.equal(classify("ChatGPT", "Plus 充值到自己的账号"), "chatgpt-plus-recharge");
  assert.equal(classify("ChatGPT", "Plus CDK", { delivery: "CDK" }), "chatgpt-plus-recharge");
  assert.equal(classify("ChatGPT", "Plus 虚拟卡"), "virtual-card");
  assert.equal(classify("ChatGPT", "Plus 订阅服务"), "other-product");
});

test("ChatGPT services, free accounts, credits and Pro tiers are separate major categories", () => {
  for (const title of ["ChatGPT 周边服务", "Codex 自助充值", "Plus 提链教程", "ChatGPT 扫码", "Plus 优惠码"]) {
    assert.equal(classify("ChatGPT", title), "chatgpt-codex-service");
  }
  assert.equal(classify("ChatGPT", "ChatGPT 普号"), "chatgpt-free-account");
  assert.equal(classify("ChatGPT", "Codex Credits 额度充值"), "chatgpt-codex-credits");
  assert.equal(classify("ChatGPT", "Team 邀请 自动拉"), "chatgpt-team-business");
  for (const [tier, titles] of [
    ["chatgpt-pro-5x", ["Pro 100刀 成品号", "Pro 5x 月卡"]],
    ["chatgpt-pro-20x", ["Pro 200刀 代充", "Pro 20x 年卡"]],
    ["chatgpt-pro-500", ["Pro 500刀", "Pro Max 50x"]],
  ] as const) for (const title of titles) assert.equal(classify("ChatGPT", title), tier);
  assert.equal(classify("ChatGPT", "Pro 月卡", { price: 200 }), "other-product");
  assert.equal(classify("ChatGPT", "Pro 5x / 20x"), "other-product");
});

test("Claude, Gemini and Grok retain distinct membership tiers", () => {
  for (const [platform, title, id] of [
    ["Claude", "Claude KYC Persona", "claude-kyc-verification"],
    ["Claude", "Claude 普号", "claude-account"],
    ["Claude", "Claude Pro 年卡", "claude-pro-month"],
    ["Claude", "Claude Max 5x 年卡", "claude-max-5x"],
    ["Claude", "Claude Max 20x 月卡", "claude-max-20x"],
    ["Claude", "Claude Team Premium", "claude-team-premium"],
    ["Claude", "Claude Team 1.25x", "claude-team-standard"],
    ["Claude", "Claude Max 年卡", "other-product"],
    ["Gemini", "Gemini Pro 年卡成品号", "gemini-pro-year"],
    ["Gemini", "Gemini Pro 充值", "gemini-pro-recharge"],
    ["Gemini", "Google AI Ultra 5x", "gemini-ultra-5x"],
    ["Gemini", "Google AI Ultra 20x", "gemini-ultra"],
    ["Grok", "Grok 普号", "grok-account"],
    ["Grok", "SuperGrok Lite", "super-grok-lite"],
    ["Grok", "Super Grok", "super-grok"],
    ["Grok", "Grok Heavy", "super-grok-heavy"],
  ]) assert.equal(classify(platform, title), id, title);
});

test("auxiliary categories distinguish mail, verification and other services", () => {
  for (const [platform, title, id] of [
    ["邮箱", "Outlook 邮箱", "outlook-account"], ["邮箱", "Gmail 邮箱", "gmail-account"],
    ["邮箱", "教育邮箱 edu", "education-email"], ["邮箱", "iCloud 邮箱", "icloud-email"],
    ["接码", "OpenAI 接码", "openai-phone-verification"], ["接码", "Google 接码", "google-phone-verification"],
    ["接码", "PayPal 接码", "paypal-phone-verification"], ["接码", "通用接码", "phone-verification"],
    ["其他", "Kiro Pro 额度号", "kiro-pro-account"], ["其他", "Kiro Free", "kiro-account"],
    ["其他", "Telegram Premium", "telegram-premium"], ["其他", "Apple 礼品卡", "gift-card"],
  ]) assert.equal(classify(platform, title), id, title);
});

test("directory families aggregate variants without losing or duplicating quotes", async () => {
  const { groupedCatalogEntries, familyByVariant } = await import("../src/lib/catalogGroups");
  const entries = groupedCatalogEntries(demo.offers, Date.parse(capturedAt));
  const gpt = entries.filter(entry => entry.platform === "ChatGPT");
  assert.equal(gpt.length, 7);
  assert.ok(gpt.some(entry => entry.id === "chatgpt-plus-family"));
  assert.ok(gpt.some(entry => entry.id === "chatgpt-pro-family"));
  assert.ok(!gpt.some(entry => entry.id === "chatgpt-plus-recharge"));
  const plus = gpt.find(entry => entry.id === "chatgpt-plus-family")!;
  assert.equal(plus.offers.length, 6);
  assert.equal(plus.channels, 6);
  assert.equal(plus.referencePrice, 108);
  const ids = entries.flatMap(entry => entry.offers.map(offer => offer.id));
  assert.equal(ids.length, demo.offers.filter(offer => offer.currency === "CNY").length);
  assert.equal(new Set(ids).size, ids.length);
  assert.equal(familyByVariant.get("chatgpt-plus-recharge")?.id, "chatgpt-plus-family");
  assert.equal(familyByVariant.get("chatgpt-pro-20x")?.variants.length, 3);
});
