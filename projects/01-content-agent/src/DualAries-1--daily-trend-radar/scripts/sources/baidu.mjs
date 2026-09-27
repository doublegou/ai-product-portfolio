import { fetchJson, fetchText } from "../core/fetch.mjs";

export const metadata = { id: "baidu", name: "百度热榜", platform: "baidu", kind: "json-api+embedded-json", language: "zh", stability: "stable" };

export async function fetchSource({ limit }) {
  let content;
  try {
    const response = await fetchJson("https://top.baidu.com/api/board?platform=wise&tab=realtime");
    content = response.data?.cards?.[0]?.content?.[0]?.content;
  } catch {
    const html = await fetchText("https://top.baidu.com/board?tab=realtime");
    const match = html.match(/<!--s-data:(.*?)-->/s);
    if (!match) throw new Error("Baidu embedded data was not found; page structure may have changed");
    const response = JSON.parse(match[1]);
    content = response.data?.cards?.[0]?.content;
  }
  if (!Array.isArray(content)) throw new Error("Baidu hot-list data has an unexpected structure");
  return content.filter((item) => !item.isTop).slice(0, limit).map((item, index) => ({
    id: item.rawUrl ?? item.url,
    title: item.word,
    url: item.rawUrl ?? item.url,
    rank: index + 1,
    summary: item.desc,
    heat: item.newHotName ?? item.labelTagName,
    language: metadata.language,
  }));
}
