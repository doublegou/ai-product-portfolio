import { load } from "cheerio";
import type { Source, Candidate } from "./types.ts";
import { safeUrl, download as downloadRequest, readLimited, assertRobots } from "./network.ts";
import { inventory } from "./stock.ts";
export const getPath = (obj: any, path: string): any =>
  path ? path.split(".").reduce((v, k) => v?.[k], obj) : obj;
export function money(v: unknown): number {
  const n = Number(String(v ?? "").replace(/[,¥￥$\s]/g, ""));
  if (!Number.isFinite(n) || n <= 0 || n > 1e7) throw new Error("无效价格");
  return Math.round(n * 100) / 100;
}
function language(v: any): string {
  if (typeof v === "string") return v;
  if (v && typeof v === "object")
    return v["zh-CN"] ?? v.zh ?? v.en ?? Object.values(v)[0] ?? "";
  return "";
}
export function parseKami(items: any[], source: Source): Candidate[] {
  return items.map((p) => ({
    external_id: String(p.id),
    raw_title: load(String(p.name ?? ""), null, false)
      .text()
      .trim(),
    price: money(p.user_price ?? p.price),
    currency: "CNY",
    ...inventory(
      Number(p.hide ?? 0) || Number(p.status ?? 1) !== 1
        ? "out_of_stock"
        : p.stock, p.stock),
    purchase_url: safeUrl(
      (source.config?.purchase_path ?? "/commodity?id={id}").replace("{id}", encodeURIComponent(p.id)),
      source.base_url,
    ).href,
  }));
}
export function parseDujiao(items: any[], source: Source): Candidate[] {
  return items.flatMap((p) =>
    (Array.isArray(p.skus) && p.skus.length ? p.skus : [null])
      .filter((s: any) => s?.is_active !== false)
      .map((s: any) => {
        // Parent stock is the sum of all variants, never evidence for an individual SKU.
        let quantity = s ? (p.fulfillment_type === "manual" ? s.manual_stock_available : s.auto_stock_available)
          : (p.fulfillment_type === "manual" ? p.manual_stock_available : p.auto_stock_available);
        if (s && p.fulfillment_type === "manual" && quantity == null && s.manual_stock_total != null && s.manual_stock_sold != null)
          quantity = Math.max(0, Number(s.manual_stock_total) - Number(s.manual_stock_sold));
        if (s && quantity != null && s.upstream_stock != null && Number(s.upstream_stock) > 0)
          quantity = Number(quantity) + Number(s.upstream_stock);
        const status = s
          ? (s.stock_status === "out_of_stock" ? s.stock_status : quantity ?? s.stock_status)
          : p.stock_status ?? quantity;
        return {
          external_id: `${p.id}:${s?.id ?? "default"}`,
          raw_title: [
            language(p.title),
            language(s?.title ?? s?.name) ||
              Object.values(s?.spec_values ?? {})
                .map(language)
                .filter(Boolean)
                .join(" / "),
          ]
            .filter(Boolean)
            .join(" · "),
          price: money(s?.price_amount ?? p.price_amount),
          currency: String(p.currency ?? "CNY").toUpperCase(),
          ...inventory(
            (s?.is_sold_out === true || p.is_sold_out === true)
              ? "out_of_stock"
              : status,
            // Product totals describe all SKUs, so never attach them to each SKU.
            quantity),
          purchase_url: new URL(
            `/products/${encodeURIComponent(p.slug ?? p.id)}`,
            source.base_url,
          ).href,
        };
      }),
  );
}
// Original storefront API returns one list for the entire shop, without pagination.
export function parse16688(items: any[], source: Source): Candidate[] {
  return items.map((p) => {
    if (!/^G\d+$/.test(String(p.goods_no)))
      throw new Error("16688 商品编号无效");
    const sourceStatus = p.stock_available_status;
    const text = sourceStatus === "out" ? "缺货" : sourceStatus === "low" ? "库存很少"
      : sourceStatus === "normal" ? "库存一般" : sourceStatus ? "库存很多" : undefined;
    const inv = inventory(sourceStatus ? (sourceStatus === "out" ? "out_of_stock" : "in_stock") : p.stock_available_quantity,
      p.stock_available_quantity, text);
    return {
      external_id: p.goods_no,
      raw_title: String(p.name ?? "").trim(),
      price: money(p.price),
      currency: "CNY",
      ...inv,
      purchase_url: new URL(`/goods/${p.goods_no}`, source.base_url).href,
      raw_data: { ...inv.raw_data, price_note: "商品标价，未包含可能由买家承担的平台手续费" },
    };
  });
}
function parseMapped(items: any[], source: Source): Candidate[] {
  const c = source.config;
  const f = c.fields ?? {
    id: "id",
    title: "name",
    price: "price",
    stock: "stock",
    url: "url",
  };
  return items.map((p) => ({
    external_id: String(getPath(p, f.id)),
    raw_title: String(getPath(p, f.title) ?? ""),
    price: money(getPath(p, f.price)) / (c.price_divisor ?? 1),
    currency: c.currency ?? "CNY",
    ...inventory(getPath(p, f.stock)),
    purchase_url: safeUrl(
      getPath(p, f.url) ||
        c.purchase_path?.replace(
          "{id}",
          encodeURIComponent(getPath(p, f.id)),
        ) ||
        source.base_url,
      source.base_url,
    ).href,
  }));
}
export function parseShopApi(items: any[], source: Source): Candidate[] {
  return items.filter(p => Number(p.price ?? p.goods_price) !== 0).map(p => {
    const count = p.extend?.stock_count ?? p.stock ?? p.stock_num;
    const n = count == null ? null : Number(count);
    const qualitative = p.extend?.show_stock_type === 0 || p.extend?.show_stock_type === "0";
    const label = qualitative && n !== null && n >= 0
      ? n === 0 ? "缺货" : n <= 5 ? "库存少量" : n < 20 ? "库存一般" : "库存充足" : undefined;
    return {
      external_id: String(p.goods_key ?? p.id), raw_title: String(p.name ?? p.goods_name ?? ""),
      price: money(p.price ?? p.goods_price), currency: "CNY",
      ...inventory(count, qualitative ? null : count, label),
      purchase_url: safeUrl(p.link || `/item/${encodeURIComponent(p.goods_key ?? p.id)}`, source.base_url).href,
    };
  });
}
export function parseHtml(html: string, source: Source): Candidate[] {
  const c = source.config;
  if (
    !c.item_selector ||
    !c.title_selector ||
    !c.price_selector ||
    !c.link_selector
  )
    throw new Error("HTML 来源需要商品、标题、价格和链接选择器");
  const $ = load(html);
  return $(c.item_selector)
    .toArray()
    .map((el) => {
      const node = $(el);
      const link = node.find(c.link_selector).attr("href") ?? node.attr("href");
      if (!link) throw new Error("商品购买链接缺失");
      let stockText = c.stock_selector
        ? node.find(c.stock_selector).text().trim()
        : "";
      if (
        typeof c.stock_prefix === "string" &&
        stockText.startsWith(c.stock_prefix)
      )
        stockText = stockText.slice(c.stock_prefix.length).trim();
      const mappedStock = Object.hasOwn(c.stock_map ?? {}, stockText)
        ? c.stock_map[stockText]
        : undefined;
      const inv = inventory(c.stock_selector ? mappedStock ?? stockText : undefined,
        stockText, stockText && !/^\d+$/.test(stockText) ? stockText.slice(0,64) : undefined);
      return {
        external_id:
          node.attr(c.id_attribute ?? "data-id") ??
          `${link}#${node.find(c.title_selector).text().trim()}`,
        raw_title: node.find(c.title_selector).text().trim(),
        price: money(node.find(c.price_selector).text().replace(/元/g, "")),
        currency: c.currency ?? "CNY",
        ...inv,
        raw_data: { ...inv.raw_data, ...(c.price_note ? {price_note:c.price_note} : {}) },
        purchase_url: safeUrl(link, source.base_url).href,
      };
    });
}
export async function collect(
  source: Source,
): Promise<{ offers: Candidate[]; complete: boolean }> {
  const deadline = Date.now() + 50000;
  const download = (url: string, init: RequestInit = {}, origin?: string) => {
    if (Date.now() >= deadline) throw new Error("原站采集超过 50 秒，保留旧报价");
    return downloadRequest(url, { ...init, signal: AbortSignal.timeout(Math.max(1, Math.min(15000, deadline - Date.now()))) }, origin);
  };
  const base = safeUrl(source.base_url);
  const c = source.config;
  const offers: Candidate[] = [];
  if (source.collector === "16688") {
    const shop = base.pathname.match(/^\/shop\/(S\d+)\/?$/)?.[1];
    if (!shop || !["16688.com.cn", "www.16688.com.cn"].includes(base.hostname))
      throw new Error("16688 来源须填写完整的 /shop/S店号 地址");
    const path = "/shopApi/goods/list";
    await assertRobots(base.href, [path]);
    const payload = JSON.parse(
      await readLimited(
        await download(
          new URL(path, base).href,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              shop_no: shop,
              goods_category_no: "",
              keywords: "",
              sort: "default",
            }),
          },
          base.origin,
        ),
      ),
    );
    if (payload.code !== 1 || !Array.isArray(payload.data?.list))
      throw new Error("16688 商品接口结构变化或店铺不可用");
    if (!payload.data.list.length)
      throw new Error("商品列表为空，保留旧报价并等待检查");
    if (payload.data.list.length > 500) throw new Error("单来源商品数超过限制");
    const rows = parse16688(payload.data.list, source);
    if (
      rows.some((o) => !o.raw_title) ||
      new Set(rows.map((o) => o.external_id)).size !== rows.length
    )
      throw new Error("商品标题缺失或编号重复");
    return { offers: rows, complete: true };
  }
  if (source.collector === "shopapi") {
    if (!c.shop_token) throw new Error("缺少 shop_token");
    const path = "/shopApi/Shop/goodsList";
    await assertRobots(base.href, [path]);
    let complete = true;
    // The original storefront has four separate product tabs; all are visited.
    for (const goods_type of ["card", "equity", "resource", "article"]) {
      let tabComplete = false;
      for (let page = 1; page <= 3; page++) {
        const payload = JSON.parse(await readLimited(await download(new URL(path, base).href, {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ token: c.shop_token, category_id: 0, goods_type, current: page, pageSize: 100, keywords: "" }),
        }, base.origin)));
        if (payload.code !== 1 || !Array.isArray(payload.data?.list)) throw new Error("ShopApi 商品接口结构变化或店铺不可用");
        offers.push(...parseShopApi(payload.data.list, source));
        const total = Number(payload.data.total);
        if (Number.isFinite(total) ? page * 100 >= total : payload.data.list.length < 100) { tabComplete = true; break; }
      }
      complete &&= tabComplete;
    }
    if (!offers.length) throw new Error("没有可采集的非零报价，保留旧报价并等待检查");
    if (offers.length > 500 || offers.some(o => !o.raw_title || o.external_id === "undefined")) throw new Error("商品数量或标识异常");
    return { offers: [...new Map(offers.map(o => [o.external_id,o])).values()], complete };
  }
  let complete = false;
  const path =
    source.collector === "kami"
      ? "/user/api/index/commodity"
      : source.collector === "dujiao"
        ? "/api/v1/public/products"
        : (c.path ?? "/");
  const target = safeUrl(path, base.href);
  if (target.origin !== base.origin) throw new Error("接口必须与来源同域");
  await assertRobots(base.href, [target.pathname]);
  if (source.collector === "html") {
    const response = await download(target.href, {}, base.origin);
    offers.push(...parseHtml(await readLimited(response), source));
    complete = c.full_snapshot === true;
  } else
    for (let page = 1; page <= 3; page++) {
      const u = new URL(target);
      let init: RequestInit = {};
      if (source.collector === "kami" || source.collector === "dujiao") {
        if (source.collector === "dujiao") u.searchParams.set("page_size", "100");
        u.searchParams.set("limit", "100");
        u.searchParams.set("page", String(page));
      }
      if (source.collector === "json" && c.page_param) {
        u.searchParams.set(c.page_param, String(page));
        if (c.limit_param)
          u.searchParams.set(c.limit_param, String(c.page_size ?? 100));
      }
      const payload = JSON.parse(
        await readLimited(await download(u.href, init, base.origin)),
      );
      const items = getPath(
        payload,
        source.collector === "kami" || source.collector === "dujiao"
          ? "data"
          : (c.items_path ?? "data"),
      );
      if (!Array.isArray(items))
        throw new Error("商品接口结构变化，未找到商品数组");
      if (!items.length) {
        if (!offers.length)
          throw new Error("商品列表为空，保留旧报价并等待检查");
        complete = true;
        break;
      }
      if (source.collector === "kami") offers.push(...parseKami(items, source));
      else if (source.collector === "dujiao")
        offers.push(...parseDujiao(items, source));
      else offers.push(...parseMapped(items, source));
      if (
        (source.collector === "json" && !c.page_param)
      ) {
        complete = c.full_snapshot === true;
        break;
      }
      if (source.collector === "dujiao" && payload.pagination) {
        if (page >= Number(payload.pagination.total_page)) { complete = true; break; }
        if (page < 3) continue;
        break;
      }
      const pageSize = source.collector === "json" ? (c.page_size ?? 100) : 100;
      if (items.length < pageSize) {
        complete = true;
        break;
      }
      if (page < 3) await new Promise((r) => setTimeout(r, 350));
    }
  const unique = new Map<string, Candidate>();
  for (const o of offers) {
    if (!o.raw_title || o.external_id === "undefined" || !o.external_id)
      throw new Error("商品标识或标题缺失");
    safeUrl(o.purchase_url);
    if (!/^[A-Z]{3}$/.test(o.currency)) throw new Error("无效币种");
    unique.set(o.external_id, o);
  }
  if (unique.size > 500) throw new Error("单来源商品数超过限制");
  return { offers: [...unique.values()], complete };
}
