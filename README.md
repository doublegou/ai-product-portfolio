# content-agent

本地运行的内容制作 Agent。当前目标是生成一篇通过 AI 审稿的小红书风格帖子草稿：

1. 读取本地 Markdown 记忆文件
2. 读取固定写作指令和可选用户主题
3. 调用 LLM 生成完整帖子草稿
4. 校验草稿结构和内容
5. AI reviewer 按发布标准审稿打分
6. AI editor 根据审稿意见改稿
7. 重复审稿和改稿，直到达到通过分数
8. 保存通过审稿的 JSON 文件

## 环境

项目目录：

```bash
/Users/doublegou/Documents/workspace/MediaOps/content-agent
```

推荐使用已经创建好的 conda 环境：

```bash
cd /Users/doublegou/Documents/workspace/MediaOps/content-agent
conda activate content-agent
python --version
pip install -r requirements.txt
cp .env.example .env
```

在 `.env` 中填写：

```bash
OPENAI_API_KEY=your_api_key_here
OPENAI_BASE_URL=https://token.sensenova.cn/v1
MODEL=deepseek-v4-flash
```

不要把真实 API Key 写进代码或提交到 git。

## 运行每日草稿

```bash
python run_daily.py
```

`run_daily.py` 默认会为每个产品独立生成一篇草稿。每个产品都会先做自动选题发现，再规划搜索方向，然后做小规模小红书搜索分析，默认目标是采集 10 条可用样本，并最多重试 5 次，再进入写作、审稿和改稿。

草稿通过审稿并保存后，默认会继续使用当前已登录 Chrome 发布到小红书。发布模块会优先使用草稿里的素材；如果草稿没有素材，会生成一张文字卡片图作为兜底发布图片。

只生成和保存草稿，不发布：

```bash
python run_daily.py --no-publish
```

调试发布页填充，但不点击最终发布：

```bash
python run_daily.py --publish-dry-run
```

自动选题分两层：

- 先做 broad hotspot discovery，看全网热点是否能自然连接某个产品
- 再做 related field discovery，看产品相关领域最近有哪些可直接写的热度点和用户语言

Broad hotspot discovery 当前使用外部全网热点源，包括 Google Trends RSS、Google News RSS、百度实时热点、微博实时热搜、YouTube mostPopular，以及 TikTok / 抖音预留源。小红书采集主要服务后续 writing research 和 strategy research。

只跑某个产品：

```bash
python run_daily.py --product "Math Puzzle"
```

单篇写作前的 research input/report 默认是临时中间过程，不会长期保存；调试时可以加 `--persist-research-artifacts`。

## 指定主题运行

```bash
python run_once.py "给 BirdTracker 写一篇小红书推广帖，角度是：把一次普通散步变成观鸟记录"
```

`run_once.py` 默认会先做一次小红书同题研究，采集相似笔记并生成临时研究 brief，再进入写作和审稿。通过审稿并保存后，默认会继续发布到小红书。调试时可以跳过研究：

```bash
python run_once.py "给 BirdTracker 写一篇小红书推广帖" --no-research
```

只生成草稿不发布：

```bash
python run_once.py "给 BirdTracker 写一篇小红书推广帖" --no-publish
```

成功后会在 `data/drafts/` 下生成一个通过审稿的 JSON 草稿文件。

如果没有配置 `OPENAI_API_KEY`，程序会提示：

```text
Missing OPENAI_API_KEY. Please set it in .env.
```

## 输出字段

```json
{
  "id": "...",
  "created_at": "...",
  "product": "Math Puzzle",
  "post_archetype": "场景种草",
  "target_scene": "睡前想玩一点轻量数字谜题",
  "traffic_hook": "不是数学考试，而是轻松填数字的短休游戏",
  "topic": "...",
  "audience": "...",
  "title": "...",
  "hook": "...",
  "body": "...",
  "takeaways": ["...", "...", "..."],
  "hashtags": ["#...", "#...", "#...", "#..."],
  "cover_text": "...",
  "reason": "...",
  "final_score": 8.6,
  "status": "approved"
}
```

## 长期策略研究

长期策略研究使用当前已登录的普通 Chrome 采集创作者和笔记样本：

```bash
python run_strategy_research.py collect --target-creators 50 --notes-per-creator 10
```

如果提示 Chrome 不允许 Apple Events 执行 JavaScript，需要在 Chrome 菜单打开：

```text
View > Developer > Allow JavaScript from Apple Events
```

这是一次性设置。打开后，采集器可以使用当前已登录 Chrome 自动搜索、滚动并抽取可见笔记卡片。

采集完成后分析长期策略样本：

```bash
python run_strategy_research.py analyze data/research/corpus/your-corpus.json
```

成功后会生成 strategy analysis，并可生成待人工确认的 strategy review。`data/research/` 已进入 `.gitignore`，不会提交。

稳定的研究结论可以沉淀到：

```text
memory/platform/xiaohongshu.md
memory/research/
```

写作 Agent 会自动读取这些记忆。详细流程见 `docs/research_workflow.md`。
