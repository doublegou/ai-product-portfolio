# content-agent：产品草稿、事实审校与失败处理

[阅读当前候选稿](2026-10-16-draft-review/post.txt) · [逐项事实审校](2026-10-16-draft-review/README.md) · [历史审改与发布准备失败](2026-07-09-birdtracker/README.md)

先看候选稿是否具体解释了产品用途，再对照九项主张的依据与处理。本案例最重要的判断是：历史模型审稿通过之后，仍有四项表达需要修订；审稿分数、事实正确和本人采纳应分别记录。

原始稿与发布准备失败已按同一 run_id 关联，另一条五轮未通过任务单独保留。当前候选稿是作品集中的 AI 辅助审校版本，未新增生产模型得分或人工采纳记录。

[产品设计](../../docs/content-agent.md) · [运行说明](../../src/content-agent/README.md) · [验收记录](../../evaluation/content-agent/README.md)

<details>
<summary>历史文件与日志依据</summary>

## 已有证据索引

| 材料 | 当前可确认的事实 | 使用限制 |
| --- | --- | --- |
| [BirdTracker 草稿](../../src/content-agent/data/drafts/2026-07-09-BirdTracker-用BirdTracker记录第一次观鸟体验.json) | 文件状态为 approved，包含标题、正文与模型评分 | 只说明内部审稿状态，不代表人工验收或发布成功 |
| [2026-07-09 日志](../../src/content-agent/data/logs/2026-07-09.jsonl) | 54 个事件，包含调用、审稿及发布相关事件 | 事件数不是完整任务数 |
| [2026-07-10 日志](../../src/content-agent/data/logs/2026-07-10.jsonl) | 50 个事件，包含研究采集及详情不完整记录 | 需按 run_id、时间和文件路径复原具体任务 |
| [2026-07-11 日志](../../src/content-agent/data/logs/2026-07-11.jsonl) | 85 个事件，包含采集和异常记录 | 不直接计算成功率或人工采纳率 |
| [发布失败结果](../../src/content-agent/data/publish_results/2026-07-09-132000-xhs-failed.json) | status 为 failed，保留错误与素材路径等字段 | 需核对关联草稿；不能拼接为任一新任务的结果 |
| [研究材料](../../src/content-agent/data/research/) | 保留采集语料、调试等历史文件 | 样本完整性和适用条件尚待逐任务核对 |

以上共 189 个日志事件，日期为历史记录日期。本轮索引未重跑生产，未修写历史结果。


</details>
