# Content Strategy Loop

这个 Agent 使用两层研究机制：周期性 benchmark 管长期设定，日常小采集管单篇写作。

## Benchmark Triggers

大规模 benchmark 管长期设定。它有两类触发方式：固定周期和事件触发。

### Fixed Weekly Trigger

目标：

- 每周一次
- 默认采集 50 个对标博主
- 每个博主采集 10 篇主页可见高互动笔记
- 采集结果增量保存，避免中途限流导致数据丢失

默认命令：

```bash
python run_benchmark.py collect
```

分析命令：

```bash
python run_benchmark.py analyze data/research/corpus/xxx.json
```

### Event Triggers

除了每周固定 benchmark，出现以下事件时也应该触发专项 benchmark：

- 账号数据明显变化：某类内容突然爆了、曝光明显下降、收藏点赞比例异常、评论问题集中变化、转粉率明显变化
- 新产品加入：需要判断新产品是否适合当前账号人设、放进哪个栏目、是否新增内容支柱
- 平台风格变化：小红书标题、封面、笔记结构、互动方式明显变化
- 某类内容连续表现不好：例如某个产品连续 5 篇表现弱，需要判断是角度、标题、场景还是产品表达问题
- 策略假设需要验证：例如“小产品宇宙”是否成立、多产品是否稀释关注、产品手记和使用教程哪个更适合

事件触发分析示例：

```bash
python run_benchmark.py analyze data/research/corpus/xxx.json \
  --trigger content_underperformance \
  --trigger-reason "ISS Tracker 连续 5 篇曝光和收藏率低于账号均值"
```

分析完成后会生成两类文件：

- `data/research/benchmark/*-benchmark-analysis.json`
- `data/strategy_reviews/*-strategy-review.json`

策略 review 是人工审批文件。它只提出建议，不自动修改 `memory/`。

策略 review 必须包含：

- trigger：触发类型
- trigger_reason：触发原因
- evidence：证据
- recommendations：建议
- proposed_memory_changes：建议修改哪些长期记忆
- risk：风险
- do_not_change：哪些设定不要改

## Human Decision

每次 weekly benchmark 之后，先看 strategy review：

- evidence：有什么证据
- recommendations：建议改什么
- proposed_memory_changes：建议改哪些记忆文件
- risk：可能副作用
- do_not_change：建议保持不变的部分

只有人工同意后，才把建议写入：

- `memory/account/persona.md`
- `memory/account/editorial_rules.md`
- `memory/account/acceptance_standards.md`
- `memory/platforms/xiaohongshu.md`

## Daily Prewrite Research

日常写每篇帖子之前，可以做小规模采集。

目标：

- 看最近类似内容如何写
- 找标题和开头表达
- 找近期热点或可借势角度
- 只服务当前这一篇，不沉淀为长期人设

当前稳定写作命令：

```bash
python run_once.py "给某个产品写一篇具体角度的小红书帖" --no-research
```

等小规模采集稳定后，可以去掉 `--no-research`。

## Quality Model

这套机制不能保证每篇都爆，但能保障：

- 不跑偏成 AI 教程号、工具推荐号、搞钱号
- 不编造产品事实、下载量、收入或用户反馈
- 每篇有具体场景、真实功能、使用动作和边界
- 大规模研究用于长期策略，小规模研究用于单篇策略
- 人工审批控制长期人格，避免被短期样本带偏
