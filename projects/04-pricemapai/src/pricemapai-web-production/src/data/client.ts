import { readSnapshotPages } from "./snapshot.ts";
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

/** Publish a dataset only after every static page has arrived successfully. */
export async function loadOffers(fetcher: typeof fetch = fetch, signal?: AbortSignal): Promise<Offer[]> {
  const rows = (await readSnapshotPages("offers", fetcher, signal)).map(validateOffer);
  if (new Set(rows.map(row => row.id)).size !== rows.length) throw Error("报价快照存在重复数据");
  return rows;
}
