import * as cheerio from "cheerio";
import { parseChineseRelativeDate } from "../core/date.mjs";
import { fetchText } from "../core/fetch.mjs";

const baseUrl = "https://www.36kr.com";

async function fetchQuick({ limit }) {
  const $ = cheerio.load(await fetchText(`${baseUrl}/newsflashes`));
  const items = [];
  $(".newsflash-item").slice(0, limit).each((index, element) => {
    const anchor = $(element).find("a.item-title");
    const href = anchor.attr("href");
    const title = anchor.text().trim();
    if (!href || !title) return;
    items.push({
      id: href,
      title,
      url: new URL(href, baseUrl).href,
      publishedAt: parseChineseRelativeDate($(element).find(".time").text()),
      rank: index + 1,
      language: "zh",
    });
  });
  return items;
}

async function fetchPopular({ limit }) {
  const date = new Intl.DateTimeFormat("en-CA", {
    year: "numeric", month: "2-digit", day: "2-digit", timeZone: "Asia/Shanghai",
  }).format(new Date());
  let html;
  try {
    html = await fetchText(`https://36kr.com/hot-list/renqi/${date}/1`, {
      headers: { referer: "https://36kr.com/" }, retries: 0,
    });
  } catch (error) {
    return {
      items: await fetchQuick({ limit }),
      warnings: [`36kr-renqi unavailable (${error.message}); fell back to 36kr-quick`],
    };
  }
  const $ = cheerio.load(html);
  const items = [];
  $(".article-item-info").slice(0, limit).each((index, element) => {
    const anchor = $(element).find("a.article-item-title.weight-bold");
    const href = anchor.attr("href");
    const title = anchor.text().trim();
    if (!href || !title) return;
    const author = $(element).find(".kr-flow-bar-author").text().trim();
    const heat = $(element).find(".kr-flow-bar-hot span").text().trim();
    items.push({
      id: href,
      title,
      url: new URL(href, "https://36kr.com").href,
      rank: index + 1,
      heat: [author, heat].filter(Boolean).join(" · "),
      summary: $(element).find("a.article-item-description.ellipsis-2").text().trim(),
      language: "zh",
    });
  });
  if (items.length) return items;
  return {
    items: await fetchQuick({ limit }),
    warnings: ["36kr-renqi returned no parseable entries; fell back to 36kr-quick"],
  };
}

export const adapters = [
  {
    metadata: { id: "36kr-quick", name: "36氪快讯", platform: "36kr", kind: "html", language: "zh", stability: "fragile" },
    fetchSource: fetchQuick,
  },
  {
    metadata: { id: "36kr-renqi", name: "36氪人气榜", platform: "36kr", kind: "html", language: "zh", stability: "fragile" },
    fetchSource: fetchPopular,
  },
];
