import { fetchJson } from "../core/fetch.mjs";

export const metadata = { id: "v2ex", name: "V2EX", platform: "v2ex", kind: "json-feed", language: "zh", stability: "stable" };

export async function fetchSource({ limit }) {
  const nodes = ["create", "ideas", "programmer", "share"];
  const feeds = await Promise.all(nodes.map((node) => fetchJson(`https://www.v2ex.com/feed/${node}.json`)));
  return feeds
    .flatMap((feed) => feed.items ?? [])
    .sort((left, right) => String(right.date_modified ?? right.date_published).localeCompare(String(left.date_modified ?? left.date_published)))
    .slice(0, limit)
    .map((item, index) => ({
      id: item.id,
      title: item.title,
      url: item.url,
      publishedAt: item.date_modified ?? item.date_published,
      rank: index + 1,
      language: metadata.language,
    }));
}
