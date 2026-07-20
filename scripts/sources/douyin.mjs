import { fetchJson, fetchResponse } from "../core/fetch.mjs";

export const metadata = {
  id: "douyin", name: "抖音热榜", platform: "douyin", kind: "json-api", language: "zh", stability: "fragile",
};

export async function fetchSource({ limit }) {
  const login = await fetchResponse("https://login.douyin.com/", { retries: 0 });
  const cookies = login.headers.getSetCookie().map((value) => value.split(";", 1)[0]);
  if (!cookies.length) throw new Error("Douyin did not issue a visitor cookie");

  const response = await fetchJson(
    "https://www.douyin.com/aweme/v1/web/hot/search/list/?device_platform=webapp&aid=6383&channel=channel_pc_web&detail_list=1",
    { headers: { cookie: cookies.join("; "), referer: "https://www.douyin.com/hot" }, retries: 0 },
  );
  return (response.data?.word_list ?? []).slice(0, limit).map((entry, index) => ({
    id: entry.sentence_id,
    title: entry.word,
    url: `https://www.douyin.com/hot/${entry.sentence_id}`,
    publishedAt: Number(entry.event_time) > 0 ? Number(entry.event_time) * 1_000 : null,
    rank: index + 1,
    heat: entry.hot_value,
    language: metadata.language,
  }));
}
