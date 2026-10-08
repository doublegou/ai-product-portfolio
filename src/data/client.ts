import type { Offer } from "./types";

export function validateOffer(value: unknown): Offer {
  const o = value as Offer | null;
  if (!o || typeof o.id !== "string" || typeof o.raw_title !== "string" ||
      !Number.isFinite(o.price) || o.price <= 0 ||
      !["platform", "plan", "delivery", "currency", "purchase_url"].every(key => typeof (o as any)[key] === "string") ||
      typeof o.review_required !== "boolean" ||
      !["in_stock", "out_of_stock", "unknown"].includes(o.stock_status) ||
      (o.comparison_key !== null && typeof o.comparison_key !== "string") ||
      (o.duration_days !== null && (!Number.isInteger(o.duration_days) || o.duration_days <= 0)) ||
      !Number.isFinite(Date.parse(o.last_seen_at)) || !Number.isFinite(Date.parse(o.expires_at)) ||
      typeof o.sources?.name !== "string" || typeof o.sources?.base_url !== "string") {
    throw new Error("报价数据格式异常，请稍后重试");
  }
  return o;
}

/** Publish a new dataset only after every page has arrived successfully. */
export async function loadOffers(fetcher: typeof fetch = fetch, signal?: AbortSignal): Promise<Offer[]> {
  const rows = new Map<string, Offer>();
  let offset = 0;
  for (let page = 0; page < 100; page++) {
    const response = await fetcher(`/api/offers?limit=1000&offset=${offset}`, { signal, cache: "no-cache" });
    if (!response.ok) throw new Error(response.status === 503 ? "数据服务尚未连接，请稍后再试" : "报价加载失败，请稍后重试");
    const data = await response.json() as { offers?: unknown[]; next_offset?: number | null };
    if (!Array.isArray(data.offers) || !("next_offset" in data)) throw new Error("报价分页格式异常");
    for (const row of data.offers) {
      const offer = validateOffer(row);
      rows.set(offer.id, offer);
    }
    if (data.next_offset === null) return [...rows.values()];
    if (!Number.isSafeInteger(data.next_offset) || data.next_offset! <= offset || !data.offers.length) throw new Error("报价分页格式异常");
    offset = data.next_offset!;
  }
  throw new Error("报价页数超出限制，请稍后重试");
}
