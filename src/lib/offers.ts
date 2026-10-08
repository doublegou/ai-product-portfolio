import { products } from "../data/products";
import type { Offer, ProductSummary } from "../data/types";

export const isFresh = (offer: Offer, now: number) =>
  Date.parse(offer.expires_at) > now;
export const isAvailable = (offer: Offer, now: number) =>
  offer.stock_status === "in_stock" && isFresh(offer, now);
export const money = (value: number, currency = "CNY") =>
  new Intl.NumberFormat("zh-CN", {
    style: "currency",
    currency,
    maximumFractionDigits: 2,
    minimumFractionDigits: value % 1 ? 2 : 0,
  }).format(value);
export const shortTime = (value: string) =>
  new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(value));
export function relativeTime(value: string | undefined, now = Date.now()) {
  if (!value || !Number.isFinite(Date.parse(value))) return "—";
  const minutes = Math.max(0, Math.floor((now - Date.parse(value)) / 60000));
  if (minutes < 1) return "刚刚";
  if (minutes < 60) return `${minutes} 分钟前`;
  if (minutes < 1440) return `${Math.floor(minutes / 60)} 小时前`;
  const days = Math.floor(minutes / 1440);
  if (days < 30) return `${days} 天前`;
  if (days < 365) return `${Math.floor(days / 30)} 个月前`;
  return `${Math.floor(days / 365)} 年前`;
}
export const durationLabel = (days: number | null) =>
  days === null
    ? "时长待确认"
    : days === 30
      ? "30 天 / 月卡"
      : days === 365
        ? "365 天 / 年卡"
        : `${days} 天`;
export const stockLabel = (o: Offer, now: number) =>
  !isFresh(o, now)
    ? "报价已过期"
    : o.stock_status === "in_stock"
      ? "有货"
      : o.stock_status === "out_of_stock"
        ? "暂时缺货"
        : "库存待确认";

export function stockDisplay(o: Offer, now: number): string {
  if (!isFresh(o, now)) return "库存待更新";
  if (o.stock_status === "out_of_stock") return "缺货";
  if (o.stock_text) return o.stock_text;
  const count = o.stock_quantity;
  if (typeof count === "number" && Number.isSafeInteger(count) && count >= 0)
    return `${count.toLocaleString("zh-CN")} 件`;
  return o.stock_status === "in_stock" ? "有货 · 数量未公布" : "未公布库存";
}

export function classifyProduct(offer: Offer): string {
  const title = offer.raw_title.normalize("NFKC").toLowerCase();
  if (/接码|接马|接碼|手机号验证/.test(title)) return "verification";
  // Pure mailbox goods are accessories. Subscription titles mentioning a mailbox remain subscriptions.
  if (offer.plan === "未知" && /邮箱|gmail|outlook|hotmail/.test(title))
    return "email";
  if (
    /资格|邀请码|优惠券|兑换券|虚拟卡|visa|试用|体验|日抛|额度充值/.test(title)
  )
    return "unclassified";
  if (offer.platform === "Claude" && offer.plan === "Max") {
    if (/20\s*[x×倍]/.test(title)) return "claude-max-20";
    if (/5\s*[x×倍]/.test(title)) return "claude-max-5";
    return "unclassified";
  }
  if (offer.platform === "Cursor" && /pro\s*\+/.test(title))
    return "cursor-pro-plus";
  return (
    products.find(
      (p) =>
        p.category === "subscription" &&
        p.platform === offer.platform &&
        p.plan === offer.plan,
    )?.id ?? "unclassified"
  );
}

export function summarize(
  offers: Offer[],
  now: number,
  currency = "CNY",
): ProductSummary[] {
  const groups = new Map<string, Offer[]>();
  for (const offer of offers) {
    const id = classifyProduct(offer);
    groups.set(id, [...(groups.get(id) ?? []), offer]);
  }
  return products
    .filter((p) => groups.has(p.id))
    .map((product) => {
      const rows = groups.get(product.id)!;
      const available = rows.filter((o) => isAvailable(o, now));
      const prices = available
        .filter((o) => o.currency === currency)
        .map((o) => o.price);
      return {
        ...product,
        offers: rows,
        channels: new Set(rows.map((o) => o.sources.base_url)).size,
        referencePrice: prices.length ? Math.min(...prices) : null,
        currency,
        available: available.length,
      };
    });
}

/** Never merge currency, term or delivery variants, even with a malformed reused key. */
export function lowestIds(offers: Offer[], now: number): Set<string> {
  const groups = new Map<string, Offer[]>();
  for (const offer of offers) {
    if (
      !offer.comparison_key ||
      offer.review_required ||
      !isAvailable(offer, now)
    )
      continue;
    const key = JSON.stringify([
      offer.comparison_key,
      offer.currency,
      offer.delivery,
      offer.duration_days,
    ]);
    groups.set(key, [...(groups.get(key) ?? []), offer]);
  }
  const ids = new Set<string>();
  for (const rows of groups.values()) {
    if (new Set(rows.map((o) => o.sources.base_url)).size < 2) continue;
    const minimum = Math.min(...rows.map((o) => o.price));
    for (const offer of rows) if (offer.price === minimum) ids.add(offer.id);
  }
  return ids;
}

export function safeLink(url: string): string | undefined {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" && !parsed.username && !parsed.password
      ? parsed.href
      : undefined;
  } catch {
    return undefined;
  }
}
