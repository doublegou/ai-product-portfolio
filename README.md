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

## 指定主题运行

```bash
python run_once.py "给 BirdTracker 写一篇小红书推广帖，角度是：把一次普通散步变成观鸟记录"
```

`run_once.py` 默认会先做一次小红书同题研究，采集相似笔记并生成临时研究 brief，再进入写作和审稿。调试时可以跳过研究：

```bash
python run_once.py "给 BirdTracker 写一篇小红书推广帖" --no-research
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
  "topic": "...",
  "audience": "...",
  "title": "...",
  "hook": "...",
  "body": "...",
  "takeaways": ["...", "...", "..."],
  "hashtags": ["#...", "#...", "#...", "#..."],
  "cover_text": "...",
  "reason": "...",
  "final_score": 8.5,
  "iterations": 2,
  "review_rounds": ["..."],
  "status": "approved"
}
```

## 对标研究分析

自动采集小红书搜索样本：

```bash
python run_collect.py xhs "独立开发者" --limit 10
```

优先使用你已经登录的普通 Chrome：

```bash
python run_collect.py xhs-current "独立开发者" --limit 10
```

如果提示 Chrome 不允许 Apple Events 执行 JavaScript，需要在 Chrome 菜单打开：

```text
View > Developer > Allow JavaScript from Apple Events
```

这是一次性设置。打开后，采集器可以使用当前已登录 Chrome 自动搜索、滚动并抽取可见笔记卡片。

先把小红书账号和笔记样本整理成 JSON：

```bash
cp samples/research_input.example.json data/research-input.json
python run_research.py data/research-input.json --validate-only
python run_research.py data/research-input.json
```

成功后会在 `data/research/reports/` 下生成平台研究报告。`data/research/` 已进入 `.gitignore`，不会提交。

稳定的研究结论可以沉淀到：

```text
memory/platform/xiaohongshu.md
memory/research/
```

写作 Agent 会自动读取这些记忆。详细流程见 `docs/research_workflow.md`。
