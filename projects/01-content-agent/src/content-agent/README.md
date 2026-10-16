# content-agent

本地运行的内容制作 Agent。当前目标是生成一篇通过 AI 审稿的小红书风格帖子草稿：

1. 读取本地 Markdown 记忆文件
2. 读取固定写作指令和可选用户主题
3. 调用 LLM 生成完整帖子草稿
4. 校验草稿结构和内容
5. AI reviewer 按发布标准审稿打分
6. AI editor 根据审稿意见改稿
7. 默认最多审稿五轮，满足全部门槛时返回；达到上限仍未通过则报错
8. 保存通过审稿的 JSON 文件

## 环境

本目录是独立的产品内容生产程序。返回[内容生产项目](../../README.md)可查看其他工作流；本程序不调度旁边的 Skill 工作流。

从作品集根目录进入，再安装依赖。所有运行命令都在本工程目录执行，保证 memory/、skills/ 和 data/ 的相对路径正确：

```bash
cd projects/01-content-agent/src/content-agent
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

首次配置时，将 `.env.example` 复制为 `.env`；已有 `.env` 时直接检查，不覆盖配置。已有满足依赖的 Python 环境也可使用。

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

单篇写作前的样本、临时 NoteInsight 和 WritingGuidance 默认不会长期保存；调试时可以加 `--persist-research-artifacts`。

## 指定主题运行

```bash
python run_once.py "给 BirdTracker 写一篇小红书推广帖，角度是：把一次普通散步变成观鸟记录"
```

`run_once.py` 默认会先做一次小红书同题研究，采集相似笔记并生成 WritingGuidance，再进入写作和审稿。通过审稿并保存后，默认会继续发布到小红书。调试时可以跳过研究：

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

这是一次性设置。打开后，采集器会使用当前已登录 Chrome 的真实滚轮和点击：
writing 先按搜索卡片的可见点赞筛选笔记，再完整读取详情正文、图片、高价值评论和回复；
strategy 从相关领域搜索结果逐个点击作者头像/名称，筛选粉丝数大于 5000 的博主，再从主页
采集高互动笔记，页面信息不足时进入详情复核。采集结束后会关闭本轮新增标签并恢复原页面。

采集完成后分析长期策略样本：

```bash
python run_strategy_research.py analyze data/research/corpus/your-corpus.json
```

分析会先通过多模态模型生成临时 CreatorStrategyInsight，再综合成 StrategyGuidance，
并可生成待人工确认的 strategy review。临时创作者洞察不会写入最终结果。
`data/research/` 已进入 `.gitignore`，不会提交。

稳定的研究结论经本人确认后，可更新当前加载器读取的账号、平台或产品资料。`src/base/memory.py` 当前读取四份固定文件（account/persona.md、account/editorial_rules.md、account/acceptance_standards.md、platforms/xiaohongshu.md）及 products/ 下的 Markdown 文件；它不会自动递归加载其他目录。单独写入 memory/research/ 不会进入写作上下文。详细流程见 `docs/research_workflow.md`。

## 离线回归

在已安装上述依赖的环境中，从本工程目录运行：

```bash
python -m unittest discover -s tests -v
```

当前 15 项测试覆盖研究结构、保存状态及审改边界，模型与发布调用使用替身。默认审稿总分至少 8.6，其他分项、blocking_issues 与本地 guard 也必须满足条件；`approved` 表示程序内审稿通过，不代表本人采纳或实际发布。
