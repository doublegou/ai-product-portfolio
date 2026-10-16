import * as cheerio from "cheerio";
import { parseChineseRelativeDate } from "../core/date.mjs";
import { fetchText } from "../core/fetch.mjs";

export const metadata = { id: "ithome", name: "IT之家", platform: "ithome", kind: "html", language: "zh", stability: "stable" };

export async function fetchSource({ limit }) {
  const $ = cheerio.load(await fetchText("https://www.ithome.com/list/"));
  const items = [];
  $("#list > div.fl > ul > li").each((_, element) => {
    if (items.length >= limit) return;
    const anchor = $(element).find("a.t");
    const url = anchor.attr("href");
    const title = anchor.text().trim();
    const dateText = $(element).find("i").text().trim();
    const isAd = url?.includes("lapin") || ["神券", "优惠", "补贴", "京东"].some((word) => title.includes(word));
    if (!url || !title || isAd) return;
    items.push({
      id: url,
      title,
      url,
      publishedAt: parseChineseRelativeDate(dateText),
      rank: items.length + 1,
      language: metadata.language,
    });
  });
  return items;
}
