---
name: daily-trend-radar
description: 聚合 15 个核心平台、18 种公开榜单入口的实时热点，识别跨平台共振、AI 与科技趋势，并生成带原始链接的内容选题或研究简报。用于用户询问今日热点、全网热榜、AI 新闻、科技趋势、开发者动态、社交热搜、跨平台趋势、热点分析、小红书/公众号/短视频选题、产品灵感，或要求从 GitHub Trending、Hacker News、AIHot、Product Hunt、V2EX、掘金、少数派、IT之家、36氪、百度、微博、知乎、抖音、哔哩哔哩和今日头条获取最新内容时。
---

# 全网热点雷达

通过本 Skill 自带的 Node.js 脚本直接请求原始公开数据源。不要依赖第三方聚合站点或凭模型记忆补写“最新”新闻。

## 执行流程

1. 根据请求选择预设：
   - 综合热点：`default`
   - 仅核心稳定源：`core`
   - 全部 18 个榜单：`all`
   - AI：`ai`
   - 科技：`tech`
   - 开发者：`developer`
   - 中文热点：`china-hot`
   - 社交热榜：`social`
   - 内容选题：`creator`
2. 从本文件所在目录运行：

   ```bash
   node scripts/run.mjs --preset ai --limit 20 --format json
   ```

3. 如果提示缺少依赖，在 Skill 根目录运行一次 `npm install --omit=dev`，然后重试。
4. 检查结果中的 `sourceStatus`。保留成功来源；明确披露失败来源，不因单源失败放弃全部结果。
5. 先按事件归并相似条目，再按跨平台来源数、榜单名次、时效和用户相关性判断优先级。
6. 输出结论时附原始链接、来源和 `fetchedAt`。没有发布时间的榜单条目只能称为“当前在榜”，不能声称事件发生于最近 24 小时。

## 常用命令

```bash
# 指定来源
node scripts/run.mjs --sources github,hackernews,aihot --limit 15 --format markdown

# 仅排除明确早于 24 小时的条目；无发布时间的当前榜单仍保留
node scripts/run.mjs --preset tech --since-hours 24 --format json

# 保存报告
node scripts/run.mjs --preset creator --format markdown --output reports/today.md

# 查看来源与预设
node scripts/list-sources.mjs

# 检查全部来源健康度
node scripts/check-sources.mjs --limit 3
```

脚本支持 `json`、`markdown` 和 `csv`。需要下游分析时优先使用 JSON；直接交付简报时使用 Markdown。

## 分析要求

- 区分“榜单热度”“发布时间”和“抓取时间”。不要把抓取时间当成新闻发布时间。
- 跨平台共振至少要求两个不同来源指向同一事件。脚本去重只是候选归并，最终语义判断由 Codex 完成。
- 对每个重要结论至少保留一个可点击原始链接；不要只给来源首页。
- 将事实、推断和选题建议分开表达。标题党或缺少正文证据的条目要降低置信度。
- 遇到 403、429、验证码或登录要求时停止该来源，不绕过访问控制，不索取或内置个人 Cookie。
- 微博在部分网络需要 Cookie；仅在用户已自行提供时读取环境变量 `WEIBO_COOKIE`，否则保留该源的失败状态并继续其他来源。
- 只采集标题、链接、时间、榜单名次、热度和短摘要，不转载全文。

需要来源维护信息时读取 [references/source-guide.md](references/source-guide.md)。需要查看尚未接入的平台与榜单时读取 [references/source-backlog.md](references/source-backlog.md)。需要评分、共振识别或内容选题规则时读取 [references/analysis-rules.md](references/analysis-rules.md)。
