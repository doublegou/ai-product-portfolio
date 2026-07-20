import { fetchFeed } from "../core/rss.mjs";

export const metadata = { id: "producthunt", name: "Product Hunt", platform: "producthunt", kind: "rss", language: "en", stability: "stable" };

export async function fetchSource({ limit }) {
  return (await fetchFeed("https://www.producthunt.com/feed"))
    .slice(0, limit)
    .map((item, index) => ({ ...item, rank: index + 1, language: metadata.language }));
}
