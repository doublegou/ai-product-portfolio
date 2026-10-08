import { products } from "./products";
import type { Offer, Snapshot } from "./types";

// Names and shop URLs from aimarketing/config/verified-sources.json.
// Prices and stock below are illustrative; they are not merchant quotations.
const merchants = [
  { name: "环球小铺", base_url: "https://gospv.com/" },
  { name: "AI能量小店", base_url: "https://dimosky.com/" },
  { name: "炼丹师小铺", base_url: "https://lianduang.com/" },
  { name: "V3小店", base_url: "https://shop.gpt.ge/" },
  { name: "Aisou智充", base_url: "https://aisou.pro/" },
  { name: "七叔数字社", base_url: "https://ai666.id/" },
  {
    name: "AI 会员代充，即买即用 - Florence AI",
    base_url: "https://faka.redeemai.me/",
  },
  { name: "NikoCard", base_url: "https://nikoers.com/" },
];
const basePrices = [
  108, 125.5, 38, 98, 1199, 49, 45, 628, 1188, 899, 99, 298, 159, 8.8, 3, 29,
];
const deliveries = [
  "代充",
  "代充",
  "CDK",
  "成品号",
  "共享",
  "代充",
  "代充",
  "未知",
];
export const capturedAt = "2026-10-07T08:00:00.000Z";
const baseTime = Date.parse(capturedAt);

export const demo: Snapshot = {
  mode: "demo",
  capturedAt,
  offers: products.flatMap((product, i): Offer[] =>
    merchants.map((source, j) => {
      const days = j === 5 ? 365 : j === 7 ? null : 30;
      const delivery =
        product.category === "subscription" ? deliveries[j] : "未知";
      const currency = j === 6 ? "USD" : "CNY";
      const review =
        j === 3 ||
        j === 7 ||
        product.plan === "Max" ||
        product.category !== "subscription";
      const multiplier =
        j === 4 ? 0.29 : j === 5 ? 9.2 : j === 6 ? 0.16 : 1 + j * 0.065;
      const price = Math.round(basePrices[i] * multiplier * 100) / 100;
      const spec = [
        "官方代充 30天",
        "代充 月卡 30天",
        "CDK 兑换码 30天",
        "成品账号 30天 地区及使用条件请核对原站",
        "共享订阅 30天",
        "代充 年卡 365天",
        "代充 月卡 30天",
        "订阅服务 具体规格待确认",
      ][j];
      return {
        id: `demo-${product.id}-${j}`,
        raw_title: `${product.name} ${product.category === "subscription" ? spec : "辅助服务 详细条件以原站说明为准"}${j === 3 ? " · 下单前请阅读商品说明，交付方式、使用范围与售后以店铺实际规则为准" : ""}`,
        price_note:
          j === 3
            ? "此条规格尚未核验，标价可能另有手续费，不参与同规格最低价比较。"
            : null,
        platform: product.platform,
        plan: product.plan,
        delivery,
        duration_days: days,
        comparison_key: review
          ? null
          : `${product.platform}:${product.plan}:${delivery}:${days}`,
        review_required: review,
        price,
        currency,
        stock_status:
          j === 2 ? "out_of_stock" : j === 7 ? "unknown" : "in_stock",
        stock_quantity: [128, 64, 0, 32, 12, 48, 24, null][j],
        purchase_url: source.base_url,
        last_seen_at: new Date(
          baseTime - (i * 3 + j * 8 + 5) * 60_000,
        ).toISOString(),
        expires_at: new Date(
          baseTime + (j === 4 ? -1 : 48) * 3600_000,
        ).toISOString(),
        sources: source,
      };
    }),
  ),
};
