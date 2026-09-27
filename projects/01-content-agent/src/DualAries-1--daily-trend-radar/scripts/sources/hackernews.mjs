import * as cheerio from "cheerio";
import { fetchText } from "../core/fetch.mjs";

export const metadata = { id: "hackernews", name: "Hacker News", platform: "hackernews", kind: "html", language: "en", stability: "stable" };

export async function fetchSource({ limit }) {
  const baseUrl = "https://news.ycombinator.com";
  const $ = cheerio.load(await fetchText(baseUrl));
  const items = [];
  $(".athing").slice(0, limit).each((index, element) => {
    const id = $(element).attr("id");
    const anchor = $(element).find(".titleline a").first();
    const href = anchor.attr("href");
    const title = anchor.text().trim();
    if (!id || !href || !title) return;
    const rawUrl = new URL(href, baseUrl).href;
    items.push({
      id,
      title,
      url: rawUrl,
      rank: index + 1,
      heat: $(`#score_${id}`).text().trim(),
      summary: `Discussion: ${baseUrl}/item?id=${id}`,
      language: metadata.language,
    });
  });
  return items;
}
