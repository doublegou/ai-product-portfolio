# Research Workflow

研究模块对应当前 `src/research/`：

```text
research_infra.py      样本结构、读取校验、通用样本分析
topic_research.py      选题研究
writing_research.py    写作研究
strategy_research.py   长期策略研究
```

## Topic Research

目标：决定今天写什么。

输入：

```text
writing_goal
product
memory/
全网泛热点样本
产品相关领域热点样本
```

输出：

```text
topic_plan
```

`topic_plan` 包含：

```text
product
topic_source
planned_topic
primary_query
supporting_queries
hot_angle_hypothesis
audience_hypothesis
risk
reason
```

## Writing Research

目标：决定这一篇具体怎么写。

输入：

```text
topic_plan
```

动作：

```text
按 primary_query / supporting_queries 做平台内小规模深度样本采集
检查是否达到 min_notes
最多重试 max_attempts
调用 research_infra.analyze_research
```

输出：

```text
writing research brief
```

这个 brief 会传给 `src/create/`，用于写初稿、审核和改稿。

默认不保存 writing research 的 input/report。只有加 `--persist-research-artifacts` 才保存调试文件。

## Strategy Research

目标：决定长期账号策略怎么进化。

采集：

```bash
python run_strategy_research.py collect --target-creators 50 --notes-per-creator 10
```

分析：

```bash
python run_strategy_research.py analyze data/research/corpus/xxx.json
```

输出：

```text
data/strategy_results/*-strategy-result.json
```

strategy result 是人工审批材料，不会自动修改 `memory/`。

## Collection Boundary

当前采集层在 `src/collect/xhs.py`。

原则：

- 优先使用当前已登录的普通 Chrome
- 不绕过登录、验证码、风控或平台限制
- 不做刷量、诱导互动、批量骚扰或批量发布
- 不复制他人长文，只分析结构和机制
- 不把样本里的未经证实数据当作事实

首次使用当前 Chrome 采集，需要打开：

```text
View > Developer > Allow JavaScript from Apple Events
```

## Future Platforms

以后接微博、百度热搜、抖音、TikTok、YouTube、Google Trends 或 RSS 时，应优先新增 `src/collect/` 下的平台采集能力。

上层 `topic_research / writing_research / strategy_research` 只负责研究策略，不直接写平台采集细节。
