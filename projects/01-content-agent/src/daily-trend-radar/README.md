# 全网热点雷达

面向 Codex 的本地热点采集与选题分析 Skill。它直接从公开数据源获取当前榜单，归并相似事件，并可输出 AI、科技、开发者和社交热点的研究简报、内容选题或结构化数据。

当前覆盖 15 个平台、18 个榜单入口；完整来源、稳定性分级和待接入清单见 [references](references/)。

## 在 Codex 里使用

新建一个 Codex 任务，直接输入：

```text
使用 $daily-trend-radar 获取今天的 AI 和科技热点，找出跨平台共振，并给出 10 个公众号选题。说明抓取时间和失败来源。
```

再测试社交榜：

```text
使用 $daily-trend-radar 检查百度、微博、知乎、抖音、B站和今日头条热榜，归并相同事件，并保留原始链接。
```

其他常用提示语：

```text
使用 $daily-trend-radar 生成今日 AI 行业简报：列出事实、推断和不确定项，并附原始链接。

使用 $daily-trend-radar 从今天的科技热点中筛出 10 个适合公众号的选题，分别给出标题、受众、核心论点和证据链接。

使用 $daily-trend-radar 只看开发者热点，找出值得跟进的开源项目和 Agent 工作流。
```

## 本地运行

需要 Node.js 20 或更高版本。

```bash
npm install
```

获取 AI 与科技热点：

```bash
node scripts/run.mjs --preset tech --limit 20 --format markdown
```

获取全部榜单并保存 JSON：

```bash
node scripts/run.mjs --preset all --limit 20 --format json --output reports/today.json
```

检查每个来源是否可用：

```bash
node scripts/check-sources.mjs --limit 3
```

查看来源、别名和预设：

```bash
node scripts/list-sources.mjs
```

## 预设

| 预设 | 用途 |
|---|---|
| `default` | 综合热点，覆盖 15 个核心平台 |
| `core` | 仅使用相对稳定的核心来源 |
| `all` | 获取全部 18 个榜单入口 |
| `ai` | AI、模型与产品动态 |
| `tech` | AI、开发者与科技热点 |
| `developer` | 开源项目、开发者社区和技术文章 |
| `china-hot` | 中文热榜与科技资讯 |
| `social` | 百度、微博、知乎、抖音、B站、今日头条 |
| `creator` | 适合内容选题筛选的来源组合 |

## 输出与状态

脚本支持 `json`、`markdown`、`csv` 三种输出格式。

JSON 结果中的关键字段：

- `fetchedAt`：本次抓取时间。
- `publishedAt`：来源提供的发布时间；为空时只能说明条目当前在榜。
- `sourceStatus`：每个来源的成功、失败或降级状态。
- `warnings`：降级或不稳定来源的提示。
- `related` 与 `sourceCount`：相似事件归并后的关联来源。

单个来源失败不会中断整个报告。遇到 403、429、验证码或登录要求时，脚本会报告状态并继续其他来源。

微博在部分网络需要用户自行提供 Cookie：

```bash
export WEIBO_COOKIE='你的 Cookie'
node scripts/check-sources.mjs --sources weibo --limit 3
```

不要把 Cookie 写入源码、配置文件或提交记录。

## 开发与验证

```bash
npm test
node scripts/check-sources.mjs --limit 3
```

维护来源时阅读：

- [来源维护指南](references/source-guide.md)
- [待接入来源](references/source-backlog.md)
- [热点分析规则](references/analysis-rules.md)
- [Skill 指令](SKILL.md)


## 作品集运行核验（2026-10-16）

三源真实采集、代理条件和失败诊断见[运行记录](../../demo/daily-trend-radar/2026-10-16-source-check/README.md)。作品集副本已修复全源失败时不保存报告的问题：JSON 仍保留 sourceStatus 和空 items，退出码保持非零；不要仅凭输出文件存在判断成功。Node 26 的 NODE_USE_ENV_PROXY=1 可按 HTTP_PROXY／HTTPS_PROXY 使用已有代理；本次未改系统代理或最低 Node 要求。

本轮只交付本地报告，不发送邮件。后续若明确要求邮件交付，仅允许用户本人 doublegou@gmail.com，不添加其他收件人、抄送或密送。
