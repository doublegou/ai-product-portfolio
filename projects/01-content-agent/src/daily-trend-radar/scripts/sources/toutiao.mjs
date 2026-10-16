import { fetchJson } from "../core/fetch.mjs";

export const metadata = {
  id: "toutiao", name: "今日头条热榜", platform: "toutiao", kind: "json-api", language: "zh", stability: "fragile",
};

export async function fetchSource({ limit }) {
  const response = await fetchJson("https://www.toutiao.com/hot-event/hot-board/?origin=toutiao_pc", {
    headers: { referer: "https://www.toutiao.com/" },
  });
  return (response.data ?? []).slice(0, limit).map((entry, index) => ({
    id: entry.ClusterIdStr,
    title: entry.Title,
    url: entry.Url ?? `https://www.toutiao.com/trending/${entry.ClusterIdStr}/`,
    rank: index + 1,
    heat: entry.HotValue,
    tags: entry.InterestCategory,
    language: metadata.language,
  }));
}
