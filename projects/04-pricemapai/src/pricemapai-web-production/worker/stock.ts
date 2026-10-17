import type { Candidate } from "./types.ts";

export function stockStatus(value: unknown): Candidate["stock_status"] {
  if (value === null || value === undefined || value === "") return "unknown";
  const text = String(value).trim();
  if (value === false || /^(out|sold_out|out_of_stock|缺货|售罄|已售罄|无货|库存不足)$/.test(text)) return "out_of_stock";
  if (value === true || /^(in_stock|有货|有库存|充足|很多|一般|很少|少量|即将售罄|库存充足|库存很多|库存一般|库存很少|库存少量|库存紧张)$/.test(text)) return "in_stock";
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? (n > 0 ? "in_stock" : "out_of_stock") : "unknown";
}

/** Preserve what the source publishes; qualitative stock is never an invented count. */
export function inventory(value: unknown, quantity: unknown = value, label?: string): Pick<Candidate, "stock_status" | "raw_data"> {
  const status = stockStatus(value);
  const n = typeof quantity === "number" || (typeof quantity === "string" && /^\d+$/.test(quantity.trim())) ? Number(quantity) : null;
  const count = n !== null && Number.isSafeInteger(n) && n >= 0 ? n : null;
  const text = label || (typeof value === "string" && /^(?:库存)?(?:充足|很多|一般|很少|有货|缺货|售罄|已售罄|无货)$/.test(value.trim()) ? value.trim() : null);
  return { stock_status: status, raw_data: {
    stock_quantity: status === "out_of_stock" ? 0 : status === "in_stock" && count === 0 ? null : count,
    stock_text: text,
  } };
}
