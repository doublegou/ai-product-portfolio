import { fetchJson } from "../core/fetch.mjs";

export const metadata = {
  id: "zhihu", name: "知乎热榜", platform: "zhihu", kind: "json-api", language: "zh", stability: "fragile",
};

export async function fetchSource({ limit }) {
  const response = await fetchJson(`https://www.zhihu.com/api/v3/feed/topstory/hot-list-web?limit=${limit}&desktop=true`, {
    headers: { referer: "https://www.zhihu.com/hot" },
  });
  return (response.data ?? []).slice(0, limit).map((entry, index) => ({
    id: entry.target?.link?.url?.match(/(\d+)\/?$/)?.[1] ?? entry.id,
    title: entry.target?.title_area?.text,
    url: entry.target?.link?.url,
    rank: index + 1,
    heat: entry.target?.metrics_area?.text,
    summary: entry.target?.excerpt_area?.text,
    language: metadata.language,
  }));
}
