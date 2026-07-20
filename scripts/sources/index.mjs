import * as aihot from "./aihot.mjs";
import * as baidu from "./baidu.mjs";
import * as bilibili from "./bilibili.mjs";
import * as douyin from "./douyin.mjs";
import * as github from "./github.mjs";
import * as hackernews from "./hackernews.mjs";
import * as ithome from "./ithome.mjs";
import * as juejin from "./juejin.mjs";
import * as kr36 from "./kr36.mjs";
import * as producthunt from "./producthunt.mjs";
import * as sspai from "./sspai.mjs";
import * as toutiao from "./toutiao.mjs";
import * as v2ex from "./v2ex.mjs";
import * as weibo from "./weibo.mjs";
import * as zhihu from "./zhihu.mjs";

const modules = [
  aihot, baidu, bilibili, douyin, github, hackernews, ithome, juejin, kr36,
  producthunt, sspai, toutiao, v2ex, weibo, zhihu,
];

const adapters = modules.flatMap((module) => module.adapters ?? [module]);
export const sources = new Map(adapters.map((source) => [source.metadata.id, source]));

export const aliases = new Map([
  ["36kr", "36kr-quick"],
  ["bilibili", "bilibili-hot-search"],
  ["github-trending-today", "github"],
  ["v2ex-share", "v2ex"],
]);

export function resolveSource(id) {
  const resolvedId = aliases.get(id) ?? id;
  return { id: resolvedId, source: sources.get(resolvedId) };
}
