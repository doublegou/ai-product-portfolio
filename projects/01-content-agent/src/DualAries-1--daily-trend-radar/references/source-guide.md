# 数据源维护指南

## 目录

- [当前来源](#当前来源)
- [稳定性原则](#稳定性原则)
- [新增或更新来源](#新增或更新来源)
- [稳定性分级](#稳定性分级)
- [待接入来源](#待接入来源)

## 当前来源

当前实现覆盖 15 个平台、18 个真实榜单入口；另接受 4 个兼容别名。

| ID | 来源 | 获取方式 | 稳定性 | 备注 |
|---|---|---|---|---|
| `aihot` | AIHot | 公共 JSON API，失败回退 RSS | stable | AI 聚合源 |
| `github` | GitHub Trending | HTML | stable | 当前榜单，无发布时间 |
| `hackernews` | Hacker News | HTML | stable | 原文与讨论热度 |
| `producthunt` | Product Hunt | RSS | stable | 产品发现 |
| `v2ex` | V2EX | JSON Feed | stable | 四个主题节点聚合 |
| `juejin` | 掘金 | 公共 Web API | stable | 开发者热文 |
| `sspai` | 少数派 | 公共 Web API | stable | 热门文章 |
| `ithome` | IT之家 | HTML | stable | 过滤明显电商广告 |
| `baidu` | 百度热榜 | Web API，回退内嵌 JSON | stable | 社会面热榜 |
| `36kr-quick` | 36氪快讯 | HTML | fragile | 兼容别名 `36kr` |
| `36kr-renqi` | 36氪人气榜 | HTML | fragile | 失败时回退快讯并返回 warning |
| `zhihu` | 知乎热榜 | Web API | fragile | 非正式接口 |
| `douyin` | 抖音热榜 | 访客 Cookie + Web API | fragile | 自动获取匿名访客 Cookie |
| `bilibili-hot-search` | B站热搜 | Web API | fragile | 兼容别名 `bilibili` |
| `bilibili-hot-video` | B站热门视频 | Web API | fragile | 提供发布时间与播放量 |
| `bilibili-ranking` | B站排行榜 | Web API | fragile | 风控时回退热门视频并返回 warning |
| `toutiao` | 今日头条热榜 | Web API | fragile | 热点事件榜 |
| `weibo` | 微博热搜 | Web API 或 HTML | conditional | 部分网络要求 `WEIBO_COOKIE` |

数据源页面或非正式 Web API 随时可能改变。`sourceStatus` 是每次运行的事实依据，不要仅凭此表宣称来源可用。

## 稳定性原则

- 优先官方 API、公开 Feed、RSS；其次普通 HTML；最后才考虑需要 Cookie 的来源。
- 将超时控制在 10 秒，临时错误最多重试 2 次。
- 401、403、429 直接停止该来源并报告，不尝试绕过。
- 每次只取用户需要的少量榜单数据，不抓正文，不高频轮询。
- 跨平台并发、同平台串行；避免 B站等多榜单入口在同一时刻互相触发风控。
- 选择器或响应结构变化时让适配器显式失败，避免输出空标题或错误链接。

## 新增或更新来源

1. 在 `scripts/sources/<id>.mjs` 导出 `metadata` 和 `fetchSource({ limit })`。
2. 返回 `id`、`title`、`url`；尽量提供 `publishedAt`、`rank`、`heat`、`summary`、`language`。
3. 在 `scripts/sources/index.mjs` 注册。
4. 只在用途明确时加入 `config/presets.json`。
5. 运行 `node scripts/check-sources.mjs --sources <id> --limit 3`。
6. 更新 `references/source-backlog.md` 中的状态与备注。

## 稳定性分级

- `stable`：当前接口无需登录，结构相对简单；仍以每次健康检查为准。
- `fragile`：非正式 Web API、HTML 或访客会话，站点改版后可能失效。
- `conditional`：在部分网络需要用户自行提供凭证。微博只读取 `WEIBO_COOKIE`，不存储、不打印、不内置 Cookie。

所有级别都独立执行。一个来源失败时，在 `sourceStatus` 中报告并继续返回其他来源；发生显式降级时通过 `sourceStatus[].warnings` 报告，不能把降级结果当成原榜单。

## 待接入来源

当前尚未接入 28 个常规平台、34 个榜单入口，另有 3 个实验候选。完整清单、分组和建议优先级见 [source-backlog.md](source-backlog.md)。
