# Research Workflow

研究模块对应当前 `src/research/`：

```text
research_infra.py      共享样本结构、输入统计/校验、结构化研究模型调用
topic_research.py      选题研究
writing_research.py    写作研究
strategy_research.py   长期策略研究
```

LLM 研究规则不写在 Python 中：

```text
skills/topic_researcher.md      选题研究规则
skills/writing_researcher.md    单篇写作研究规则
skills/strategy_researcher.md   创作者分析、长期策略综合和策略 review 规则
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
同选题详细笔记
对应产品、账号和平台记忆
```

动作：

```text
按 primary_query / supporting_queries 做平台内小规模深度样本采集
检查是否达到 min_notes
最多重试 max_attempts
分批生成临时 NoteInsight
把每篇笔记的实际图片按稳定标签发送给多模态模型
综合全部 NoteInsight 与 topic_plan
```

输出：

```text
WritingGuidance
```

`WritingGuidance` 包含本篇的流量逻辑、目标场景、标题/封面/开头指导、
整组图片指导、正文结构、产品连接、收藏与讨论机制、表达规则和禁区。

`NoteInsight` 只在当前进程中用于综合，不是正式研究产物，也不会默认保存。

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

动作：

```text
逐个或小批次分析创作者主页资料、完整笔记和实际图片
生成只存在于当前进程的 CreatorStrategyInsight
综合全部 CreatorStrategyInsight 与本地产品记忆
生成 StrategyGuidance
可选生成 StrategyReview
```

`--batch-size` 表示每次多模态分析包含多少个创作者，默认是 1，避免单次请求
混入过多账号和图片。

输出：

```text
data/strategy_results/*-strategy-result.json
```

strategy result 是人工审批材料，不会自动修改 `memory/`。

## Collection Boundary

当前采集层在 `src/collect/xhs.py`。

原则：

- 优先使用当前已登录的普通 Chrome
- `collect_infra.py` 只提供浏览器窗口、真实鼠标、滚轮、键盘和页面快照能力
- 平台页面语义、筛选标准和详情字段由对应平台采集文件负责
- 小红书 writing 按搜索卡片的可见点赞筛选，并完整浏览正文、图片、高价值评论和回复
- 小红书 strategy 从相关领域结果卡片点击作者头像/名称，筛选目标博主后采集主页帖子；可见指标不足时用详情数据复核
- 每轮结束只关闭本轮新增的小红书标签或窗口，并恢复采集前的活动页面
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

`plan_topic(...)`、`analyze_writing_research(...)` 和
`analyze_strategy_corpus(...)` 都可以直接接收已经采集的数据，独立完成研究。
外层 run 函数可以继续组合采集与研究，但平台页面细节仍只属于 `src/collect/`。
