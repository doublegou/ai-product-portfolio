import { XMLParser } from "fast-xml-parser";
import { fetchText } from "./fetch.mjs";

const parser = new XMLParser({
  attributeNamePrefix: "",
  textNodeName: "$text",
  ignoreAttributes: false,
});

const asArray = (value) => (value == null ? [] : Array.isArray(value) ? value : [value]);
const text = (value) => (value && typeof value === "object" ? value.$text : value);
const link = (value) => {
  if (Array.isArray(value)) return link(value[0]);
  return value && typeof value === "object" ? value.href : value;
};

export async function fetchFeed(url, options = {}) {
  const xml = await fetchText(url, options);
  const parsed = parser.parse(xml);
  let channel = parsed.rss?.channel ?? parsed.feed;
  if (Array.isArray(channel)) [channel] = channel;
  if (!channel) throw new Error(`Unsupported RSS/Atom document: ${url}`);

  return asArray(channel.item ?? channel.entry).map((item) => ({
    id: text(item.guid) ?? text(item.id) ?? link(item.link),
    title: text(item.title),
    url: link(item.link),
    publishedAt: text(item.updated) ?? text(item.published) ?? text(item.pubDate) ?? text(item.created),
    summary: text(item.summary) ?? text(item.description),
  }));
}

