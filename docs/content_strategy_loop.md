# Content Agent Architecture

这个项目现在分成四层：

```text
src/base/      基础设施：LLM 调用、JSON 解析、memory 读取、草稿保存
src/collect/   平台采集：当前主要是小红书 Chrome 采集
src/research/  研究流程：选题研究、写作研究、长期策略研究
src/create/    创作流程：写初稿、审核、改稿、运行循环
```

运行入口只有三个：

```text
run_daily.py              每天为产品批量生成帖子
run_once.py               按指定主题生成一篇帖子
run_strategy_research.py  长周期策略研究
```

## Daily Content Flow

`run_daily.py` 默认会为这些产品各自生成一篇：

```text
ISS Tracker
BirdTracker
Math Puzzle
Soulnio
```

每个产品的流程是：

```text
topic_research
  -> broad hotspot discovery
  -> related field discovery
  -> topic_plan

writing_research
  -> 根据 topic_plan 搜索小规模样本
  -> 分析标题、开头、正文结构、封面、用户问题
  -> writing research brief

create
  -> write 初稿
  -> review 审核
  -> revise 改稿
  -> 通过后保存 approved draft
```

只跑某个产品：

```bash
python run_daily.py --product "Math Puzzle"
```

临时跳过平台研究：

```bash
python run_daily.py --no-research
```

## Single Post Flow

`run_once.py` 用于临时写一篇指定主题：

```bash
python run_once.py "给 BirdTracker 写一篇适合周末户外散步场景的小红书帖"
```

默认也会先做：

```text
topic_research -> writing_research -> create
```

## Research Layers

研究分三层：

```text
topic_research.py
  决定今天写什么。先看全网泛热点，再看产品相关领域，输出 topic_plan。

writing_research.py
  决定这篇怎么写。围绕 topic_plan 做目标平台的小规模深度样本研究，输出给 create 使用的 brief。

strategy_research.py
  决定长期怎么进化。采集更大规模的创作者和笔记样本，生成 strategy result。
```

`research_infra.py` 不是第四层研究，它只提供样本结构、输入校验和通用样本分析能力。

## Strategy Research

长期策略研究用于更新账号人设、语气、栏目、写作规则和验收标准的判断依据。它不参与每次日常写作，也不会自动改 `memory/`。

采集长期样本：

```bash
python run_strategy_research.py collect --target-creators 50 --notes-per-creator 10
```

分析长期样本：

```bash
python run_strategy_research.py analyze data/research/corpus/xxx.json
```

带触发原因的专项分析：

```bash
python run_strategy_research.py analyze data/research/corpus/xxx.json \
  --trigger content_underperformance \
  --trigger-reason "ISS Tracker 连续 5 篇曝光和收藏率低于账号均值"
```

每次分析只保存一个结果文件：

```text
data/strategy_results/*-strategy-result.json
```

这个文件包含：

```text
analysis
review
trigger
trigger_reason
corpus_path
generated_at
```

人工确认后，才把稳定结论写入 `memory/`。

## Persistence Rules

默认只保留最终内容产物：

```text
data/drafts/
```

日常 topic research 和 writing research 默认使用临时目录，跑完清理。只有显式传入：

```bash
--persist-research-artifacts
```

才会保存本次研究中间文件，用于排查采集或分析问题。

最终 draft 不保存审核轮次、改稿过程、research input 或 research report。

## Quality Model

这套机制不能保证每篇都爆，但要保障：

- 不跑偏成 AI 教程号、工具推荐号、搞钱号
- 不编造产品事实、下载量、收入、用户反馈或官方合作
- 每篇有具体场景、真实功能、使用动作和边界
- 小规模研究服务单篇内容，长期策略研究服务账号方向
- 长期策略变更必须经过人工确认
