import * as cheerio from "cheerio";
import { fetchText } from "../core/fetch.mjs";

export const metadata = { id: "github", name: "GitHub Trending", platform: "github", kind: "html", language: "en", stability: "stable" };

export async function fetchSource({ limit }) {
  const html = await fetchText("https://github.com/trending?spoken_language_code=");
  const $ = cheerio.load(html);
  const items = [];
  $("main .Box div[data-hpc] > article").slice(0, limit).each((index, element) => {
    const anchor = $(element).find("> h2 a");
    const path = anchor.attr("href");
    const title = anchor.text().replace(/\s+/g, " ").trim();
    if (!path || !title) return;
    items.push({
      id: path,
      title,
      url: new URL(path, "https://github.com").href,
      rank: index + 1,
      heat: $(element).find("[href$='/stargazers']").text().replace(/\s+/g, " ").trim(),
      summary: $(element).find("> p").text().replace(/\s+/g, " ").trim(),
      language: metadata.language,
    });
  });
  return items;
}
