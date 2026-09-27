import { fetchJson } from "../core/fetch.mjs";

export const metadata = { id: "sspai", name: "少数派", platform: "sspai", kind: "json-api", language: "zh", stability: "stable" };

export async function fetchSource({ limit }) {
  // The www host avoids intermittent TLS resets seen on some networks; it
  // redirects to the same public endpoint.
  const url = new URL("https://www.sspai.com/api/v1/article/tag/page/get");
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("offset", "0");
  url.searchParams.set("created_at", String(Date.now()));
  url.searchParams.set("tag", "热门文章");
  url.searchParams.set("released", "false");
  const response = await fetchJson(url);
  return (response.data ?? []).slice(0, limit).map((item, index) => ({
    id: item.id,
    title: item.title,
    url: `https://sspai.com/post/${item.id}`,
    rank: index + 1,
    language: metadata.language,
  }));
}
