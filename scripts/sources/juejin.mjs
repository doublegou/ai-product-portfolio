import { fetchJson } from "../core/fetch.mjs";

export const metadata = { id: "juejin", name: "掘金", platform: "juejin", kind: "json-api", language: "zh", stability: "stable" };

export async function fetchSource({ limit }) {
  const response = await fetchJson("https://api.juejin.cn/content_api/v1/content/article_rank?category_id=1&type=hot&spider=0");
  return (response.data ?? []).slice(0, limit).map((entry, index) => ({
    id: entry.content.content_id,
    title: entry.content.title,
    url: `https://juejin.cn/post/${entry.content.content_id}`,
    rank: index + 1,
    language: metadata.language,
  }));
}
