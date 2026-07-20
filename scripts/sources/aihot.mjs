import { fetchJson } from "../core/fetch.mjs";
import { fetchFeed } from "../core/rss.mjs";

export const metadata = { id: "aihot", name: "AIHot", platform: "aihot", kind: "json-api+rss", language: "mixed", stability: "stable" };

export async function fetchSource({ limit }) {
  try {
    const response = await fetchJson(`https://aihot.virxact.com/api/public/items?mode=all&take=${limit}`);
    const items = (response.items ?? []).filter((item) => item.id && item.title && item.url);
    if (!items.length) throw new Error("AIHot API returned no items");
    return items.slice(0, limit).map((item, index) => ({
      id: item.id,
      title: item.title,
      url: item.url,
      publishedAt: item.publishedAt,
      rank: index + 1,
      heat: item.category ? `${item.source} · ${item.category}` : item.source,
      summary: item.summary,
      language: metadata.language,
    }));
  } catch {
    return (await fetchFeed("https://aihot.virxact.com/feed/all.xml"))
      .slice(0, limit)
      .map((item, index) => ({ ...item, rank: index + 1, language: metadata.language }));
  }
}
