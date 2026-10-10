import { isCodexCredits } from './codex-credits';
import { platforms } from "../data/products";
import standards from "../data/standard-products.json";
import { classifyProduct, isAvailable, isFresh } from "./offers";
import type { Offer, ProductSummary, Product } from "../data/types";

export const catalogTabs = [
  { id: "", label: "全部" },
  ...platforms.map((platform) => ({ id: platform, label: platform })),
  { id: "other", label: "其他" },
];

export function productCategory(product: Product): string {
  if (platforms.includes(product.platform)) return product.platform;
  return "other";
}

export const otherCatalogTabs = [
  { id: "", label: "全部" },
  { id: "email", label: "邮箱" },
  { id: "verification", label: "接码" },
  { id: "other", label: "其他" },
];

export function productSubcategory(product: Product): string {
  if (product.platform === "邮箱" || product.id === "email") return "email";
  if (product.platform === "接码" || product.id === "verification") return "verification";
  return "other";
}

export function selectedCategory(params: URLSearchParams): string {
  const category = params.get("category") ?? "";
  if (["email", "verification", "other", "unclassified"].includes(category)) return "other";
  const platform = params.get("platform") ?? "";
  return platforms.includes(platform) ? platform : "";
}

export function selectCategory(params: URLSearchParams, category: string): URLSearchParams {
  const next = new URLSearchParams(params);
  next.delete("saved");
  next.delete("currency");
  next.delete("category");
  next.delete("platform");
  next.delete("page");
  next.delete("subtype");
  if (platforms.includes(category)) next.set("platform", category);
  else if (["email", "verification", "other", "unclassified"].includes(category)) next.set("category", "other");
  return next;
}

export type CatalogProduct = Product & { subtitle: string; kind?: string };
export type CatalogEntry = CatalogProduct & ProductSummary & {
  key: string;
  priceKind: "lowest" | "reference" | "none";
  priceOffer: Offer | null;
};

// Standard merchandise taxonomy transcribed from https://priceai.cc/channels on 2026-10-08.
// Empty categories remain visible: catalog structure is independent of available quotes.
export const catalogProducts: CatalogProduct[] = standards.map(item => ({
  id: item.id,
  name: item.id === "chatgpt-plus" ? "ChatGPT Plus 成品号" : item.id === "chatgpt-plus-recharge" ? "ChatGPT Plus 充值" : item.name,
  platform: item.id === "cursor-account" ? "Cursor" : item.platform,
  plan: item.subtitle,
  kind: item.kind,
  category: item.id === "other-product" ? "unclassified" : item.kind === "订阅/会员" ? "subscription" : "accessory",
  subtitle: item.id === "chatgpt-plus-recharge" ? "充值 · 代充 · 订阅兑换" : item.subtitle,
  description: item.id === "chatgpt-plus-recharge" ? "充值 · 代充 · 订阅兑换" : item.subtitle,
  tagline: item.id === "chatgpt-plus-recharge" ? "充值 · 代充 · 订阅兑换" : item.subtitle,
}));
export const catalogProductById = new Map(catalogProducts.map(product => [product.id, product]));
const aliases: Record<string, string> = {
  "chatgpt-plus-account": "chatgpt-plus", "chatgpt-team": "chatgpt-team-business",
  "claude-pro": "claude-pro-month", "claude-max-5": "claude-max-5x", "claude-max-20": "claude-max-20x",
  "gemini-pro-account": "gemini-pro-year", "grok-pro": "super-grok",
  "cursor-pro": "cursor-account", "cursor-pro-plus": "cursor-account",
  email: "email-account", verification: "phone-verification", unclassified: "other-product",
};
for (const [alias, id] of Object.entries(aliases)) catalogProductById.set(alias, catalogProductById.get(id)!);

export function catalogProductId(offer: Offer): string {
  if (isCodexCredits(offer.raw_title)) return 'chatgpt-codex-credits';
  const title = offer.raw_title.normalize("NFKC").toLowerCase();
  const text = `${offer.plan} ${title}`.toLowerCase();
  const has = (pattern: RegExp) => pattern.test(text);
  const recharge = ["代充", "CDK"].includes(offer.delivery) || has(/充值|代充|直充|兑换码/);
  const account = ["成品号", "共享"].includes(offer.delivery) || has(/成品|账号|普号|试用|体验|日抛|次抛|网页号/);
  const basic = has(/普号|普通账号|\bfree\b/);
  if (has(/虚拟卡|visa|mastercard/)) return "virtual-card";
  if (has(/礼品卡/)) return "gift-card";
  if (has(/接码|接马|接碼|手机号验证/) && !has(/plus|pro|team|会员|订阅/)) {
    if (has(/paypal/)) return "paypal-phone-verification";
    if (has(/openai|chatgpt|codex/)) return "openai-phone-verification";
    if (has(/google|gemini/)) return "google-phone-verification";
    return "phone-verification";
  }
  if (has(/kyc|persona|真人验证/)) return offer.platform === "Claude" ? "claude-kyc-verification" : "identity-verification";
  if (offer.platform === "ChatGPT") {
    if (has(/team|business|k12/)) return "chatgpt-team-business";
    if (has(/周边|自助|教程|提链|扫码|邀请|优惠码|优惠券|资格/)) return "chatgpt-codex-service";
    if (has(/\bpro\b|pro\d/)) {
      const tiers = new Set<string>();
      if (has(/(?:^|[^\d.])100\s*(?:刀|美元|usd)|\$\s*100\b|(?:^|[^\d.])5\s*[x×倍]/)) tiers.add("chatgpt-pro-5x");
      if (has(/(?:^|[^\d.])200\s*(?:刀|美元|usd)|\$\s*200\b|(?:^|[^\d.])20\s*[x×倍]/)) tiers.add("chatgpt-pro-20x");
      if (has(/(?:^|[^\d.])500\s*(?:刀|美元|usd)|\$\s*500\b|(?:^|[^\d.])(?:25|50)\s*[x×倍]|pro\s*max/)) tiers.add("chatgpt-pro-500");
      return tiers.size === 1 ? [...tiers][0] : "other-product";
    }
    if (has(/team|business|k12/)) return "chatgpt-team-business";
    if (has(/\bgo\b/)) return "chatgpt-go";
    if (has(/plus/)) {
      if (has(/日抛|次抛|试用|体验/) || ["成品号", "共享"].includes(offer.delivery)) return "chatgpt-plus";
      if (recharge) return "chatgpt-plus-recharge";
      if (account) return "chatgpt-plus";
      return "other-product";
    }
    if (basic || account) return "chatgpt-free-account";
  }
  if (offer.platform === "Claude") {
    if (has(/team/)) {
      if (has(/premium|6\.25\s*[x×倍]/)) return "claude-team-premium";
      if (has(/standard|1\.25\s*[x×倍]/)) return "claude-team-standard";
      return "other-product";
    }
    if (has(/max/)) {
      if (has(/20\s*[x×倍]/)) return "claude-max-20x";
      if (has(/(?:^|[^\d.])5\s*[x×倍]/)) return "claude-max-5x";
      return "other-product";
    }
    if (has(/\bpro\b/)) return "claude-pro-month";
    if (basic || account || has(/兑换号/)) return "claude-account";
  }
  if (offer.platform === "Gemini") {
    if (has(/ultra/)) return has(/(?:^|[^\d.])5\s*[x×倍]/) ? "gemini-ultra-5x" : "gemini-ultra";
    if (has(/\bpro\b/)) {
      if (has(/试用|体验|日抛|次抛/) || ["成品号", "共享"].includes(offer.delivery)) return "gemini-pro-year";
      if (recharge) return "gemini-pro-recharge";
      if (account) return "gemini-pro-year";
    }
  }
  if (offer.platform === "Grok") {
    if (has(/heavy/)) return "super-grok-heavy";
    if (has(/lite/)) return "super-grok-lite";
    if (basic) return "grok-account";
    if (has(/super|pro/)) return "super-grok";
    if (account) return "grok-account";
  }
  if (offer.platform === "Cursor" || has(/cursor/)) return "cursor-account";
  if (classifyProduct(offer) === "email" || offer.platform === "邮箱") {
    if (has(/outlook|hotmail|microsoft/)) return "outlook-account";
    if (has(/icloud/)) return "icloud-email";
    if (has(/edu|教育/)) return "education-email";
    if (has(/gmail|google/)) return "gmail-account";
    return "email-account";
  }
  if (classifyProduct(offer) === "verification") return "phone-verification";
  for (const [pattern, id] of [
    [/kiro.*(?:pro|额度|积分)/, "kiro-pro-account"], [/kiro/, "kiro-account"], [/windsurf/, "windsurf-account"],
    [/perplexity/, "perplexity-account"], [/suno/, "suno-account"], [/dreamina|即梦|seedance/, "dreamina-account"],
    [/apple\s*id|苹果账号/, "apple-id-account"], [/telegram.*(?:premium|pro|stars)|纸飞机.*订阅/, "telegram-premium"],
    [/telegram|纸飞机/, "telegram-account"], [/(?:\bx\b|推特).*premium/, "x-twitter-premium"], [/twitter|推特/, "x-twitter-account"],
  ] as [RegExp, string][]) if (has(pattern)) return id;
  return "other-product";
}

export function summarizeCatalogEntry(product: CatalogProduct, offers: Offer[], now: number): CatalogEntry {
  offers = offers.filter(offer => offer.currency === "CNY");
  const selectedCurrency = "CNY";
  const available = offers.filter(offer => isAvailable(offer, now));
  const candidates = available.length ? available : offers.filter(offer => offer.stock_status === "unknown" && isFresh(offer, now));
  const priceOffer = [...candidates].sort((a, b) => a.price - b.price)[0] ?? null;
  return { ...product, key: product.id, offers, currency: selectedCurrency,
    channels: new Set(offers.map(offer => offer.sources.base_url)).size,
    available: available.length, referencePrice: priceOffer?.price ?? null, priceOffer,
    priceKind: available.length ? "lowest" : priceOffer ? "reference" : "none" };
}

export function catalogEntries(offers: Offer[], now: number): CatalogEntry[] {
  const groups = new Map<string, Offer[]>();
  for (const offer of offers) {
    const id = catalogProductId(offer);
    groups.set(id, [...(groups.get(id) ?? []), offer]);
  }
  return catalogProducts.map(product => summarizeCatalogEntry(product, groups.get(product.id) ?? [], now));
}

export function catalogPriceStatus(product: CatalogEntry, now: number): string {
  if (!product.offers.length) return "暂无报价";
  const fresh = product.offers.filter(offer => isFresh(offer, now));
  if (!fresh.length) return "报价待更新";
  if (fresh.every(offer => offer.stock_status === "out_of_stock")) return "暂时缺货";
  return "暂无可用价格";
}

export function filterCatalogEntries(entries: CatalogEntry[], params: URLSearchParams, now: number): CatalogEntry[] {
  const category = selectedCategory(params);
  const subtype = params.get("subtype");
  const query = (params.get("q") ?? "").trim().toLowerCase();
  return entries
    .filter(product => (!category || productCategory(product) === category) &&
      (category !== "other" || !subtype || productSubcategory(product) === subtype))
    .map(product => {
      if (!product.offers.length) {
        return `${product.name} ${product.description}`.toLowerCase().includes(query) ? product : null;
      }
      const offers = product.offers.filter(offer =>
        `${product.name} ${product.description} ${offer.sources.name} ${offer.raw_title}`.toLowerCase().includes(query));
      return offers.length ? summarizeCatalogEntry(product, offers, now) : null;
    })
    .filter(product => product !== null);
}
