import * as cheerio from "cheerio";
import { fetchJson, fetchText, HttpError } from "../core/fetch.mjs";

export const metadata = {
  id: "weibo", name: "微博热搜", platform: "weibo", kind: "json-api/html", language: "zh", stability: "conditional",
};

function fromJson(response, limit) {
  const list = response.data?.realtime ?? response.data?.hotgovs ?? [];
  return list.slice(0, limit).map((entry, index) => ({
    id: entry.word_scheme ?? entry.word,
    title: entry.note ?? entry.word,
    url: `https://s.weibo.com/weibo?q=${encodeURIComponent(entry.word_scheme ?? entry.word)}`,
    rank: index + 1,
    heat: entry.num ? String(entry.num) : entry.icon_desc,
    language: metadata.language,
  }));
}

function fromHtml(html, limit) {
  const $ = cheerio.load(html);
  const items = [];
  $("#pl_top_realtimehot table tbody tr").slice(1).each((_, row) => {
    if (items.length >= limit) return;
    const anchor = $(row).find("td.td-02 a").filter((__, element) => {
      const href = $(element).attr("href");
      return href && !href.includes("javascript:void(0)");
    }).first();
    const href = anchor.attr("href");
    const title = anchor.text().trim();
    if (!href || !title) return;
    items.push({
      id: title,
      title,
      url: new URL(href, "https://s.weibo.com").href,
      rank: items.length + 1,
      heat: $(row).find("td.td-02 span").text().trim() || $(row).find("td.td-03").text().trim(),
      language: metadata.language,
    });
  });
  return items;
}

export async function fetchSource({ limit }) {
  const cookie = process.env.WEIBO_COOKIE?.trim();
  const headers = { referer: "https://s.weibo.com/top/summary?cate=realtimehot", ...(cookie ? { cookie } : {}) };
  try {
    const items = fromJson(await fetchJson("https://weibo.com/ajax/side/hotSearch", { headers, retries: 0 }), limit);
    if (items.length) return items;
  } catch (error) {
    if (!cookie && error instanceof HttpError && [401, 403].includes(error.status)) {
      throw new Error("Weibo requires WEIBO_COOKIE in this network; no cookie is embedded by the skill");
    }
  }

  if (!cookie) throw new Error("Weibo requires WEIBO_COOKIE in this network; no cookie is embedded by the skill");
  const items = fromHtml(await fetchText("https://s.weibo.com/top/summary?cate=realtimehot", { headers, retries: 0 }), limit);
  if (!items.length) throw new Error("Weibo returned no hot-list rows; cookie may be expired");
  return items;
}
