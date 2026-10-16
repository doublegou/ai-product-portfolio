import { fetchJson } from "../core/fetch.mjs";

function compactNumber(value) {
  return new Intl.NumberFormat("zh-CN", { notation: "compact", maximumFractionDigits: 1 }).format(value ?? 0);
}

async function fetchHotSearch({ limit }) {
  const response = await fetchJson(`https://s.search.bilibili.com/main/hotword?limit=${limit}`);
  const combined = [...(response.top_list ?? []), ...(response.list ?? [])];
  const seen = new Set();
  return combined.filter((entry) => {
    const key = entry.keyword ?? entry.show_name;
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, limit).map((entry, index) => ({
    id: entry.keyword ?? entry.show_name,
    title: entry.show_name ?? entry.keyword,
    url: `https://search.bilibili.com/all?keyword=${encodeURIComponent(entry.keyword ?? entry.show_name)}`,
    rank: index + 1,
    heat: entry.heat_score ? String(entry.heat_score) : null,
    language: "zh",
  }));
}

function videoItems(response, limit) {
  return (response.data?.list ?? []).slice(0, limit).map((video, index) => ({
    id: video.bvid,
    title: video.title,
    url: `https://www.bilibili.com/video/${video.bvid}`,
    publishedAt: video.pubdate * 1_000,
    rank: index + 1,
    heat: `${video.owner?.name ?? ""} · ${compactNumber(video.stat?.view)}观看 · ${compactNumber(video.stat?.like)}点赞`,
    summary: video.desc,
    language: "zh",
  }));
}

async function fetchHotVideo({ limit }) {
  return videoItems(await fetchJson(`https://api.bilibili.com/x/web-interface/popular?ps=${limit}&pn=1`), limit);
}

async function fetchRanking({ limit }) {
  try {
    const response = await fetchJson("https://api.bilibili.com/x/web-interface/ranking/v2", {
      headers: { referer: "https://www.bilibili.com/v/popular/rank/all" }, retries: 0,
    });
    const items = videoItems(response, limit);
    if (response.code !== 0 || !items.length) throw new Error(`Bilibili ranking API code ${response.code ?? "unknown"}`);
    return items;
  } catch (error) {
    return {
      items: await fetchHotVideo({ limit }),
      warnings: [`bilibili-ranking unavailable (${error.message}); fell back to bilibili-hot-video`],
    };
  }
}

export const adapters = [
  {
    metadata: { id: "bilibili-hot-search", name: "B站热搜", platform: "bilibili", kind: "json-api", language: "zh", stability: "fragile" },
    fetchSource: fetchHotSearch,
  },
  {
    metadata: { id: "bilibili-hot-video", name: "B站热门视频", platform: "bilibili", kind: "json-api", language: "zh", stability: "fragile" },
    fetchSource: fetchHotVideo,
  },
  {
    metadata: { id: "bilibili-ranking", name: "B站排行榜", platform: "bilibili", kind: "json-api", language: "zh", stability: "fragile" },
    fetchSource: fetchRanking,
  },
];
