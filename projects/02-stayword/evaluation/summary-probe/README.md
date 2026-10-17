# 摘要质量诊断：为什么拒绝一版“更严格”的提示词

[返回项目](../../README.md) · [验证总览](../README.md)

**决策：不采用本次候选提示词。** 在实际运行中，追加约束没有稳定消除错误，额外出现循环重复和禁止动作反转。保留原工程，并将事实核验、语言控制和重复终止作为下一轮质量工作的优先级。

## 这次实际测了什么

2026-10-17，在 Apple M5 Pro / macOS 上，使用仓库随包的 Qwen3.5-0.8B 4-bit 权重，抽取 iOS 源码中的 system 与单文档提示词，通过 Python MLX 实际推理。温度 0.2、top-p 0.9、重复惩罚 1.05 / 窗口 64，与代码参数对应；关闭 thinking。运行库版本、源文件与权重 SHA-256 保存在结果 JSON 中。

这是**模型与提示词的离线诊断**：输入是本次编写的合成转写文本，不是用户录音；未经过 ASR、Swift 运行时、手机 UI 或长文本分块。Python 运行设置额外的 1,024 token 上限，不能将其耗时作为手机端性能成绩。

先冻结 8 条发现样本，每条 2 个随机种子。检视原始结果后编写一份通用约束候选，不修改原应用；再冻结 4 条额外检查样本，候选在额外样本执行前固定。两版均运行全部 12 条，共 **48 次真实推理**。额外样本仍由同一个助手编写，不是独立外部盲测集。

## 结果与判断

| 检查项 | 原始提示词：24 次 | 约束候选：24 次 | 判断 |
| --- | ---: | ---: | --- |
| 初审标记的高影响事实问题 | 5 次 | 8 次 | 没有支持替换原版的证据 |
| 英文输入保持英文输出 | 0 / 4 | 0 / 4 | 追加语言指令仍未解决 |
| 达到 1,024 token 上限 | 0 次 | 1 次 | 候选 S05 出现明显循环重复 |

“高影响”指无依据新增或反转金额、时间、责任人、状态、领域或行动要求。遗漏和存在歧义的时态不自动归入这一计数；未标记也不表示整条完全正确。判定为 **Codex 助手初审**，不是人工双评，也不是权威准确率。每条标记有原文摘录与理由，可在[逐项初审](review.json)复核。

| 样本 | 输入的关键约束 | 实际输出中的问题 | 产品影响 |
| --- | --- | --- | --- |
| S05 / 原版 seed 29 | 恶意文字仅为攻击样例 | 将“只输出已付款金额”转述为应遵守的规则 | 资料内容被误当作操作要求 |
| S06 / 原版 seed 17 | RTF 是识别耗时 / 音频时长，从 0.8 降到 0.5 | 写成“识别率分数”，并称未改善 | 技术缩写与改善方向被改变 |
| S08 / 原版 seed 29 | pilot 为试点，采购设备类型未说明 | 补出飞行和“无人机设备” | 流畅的摘要混入不存在的领域事实 |
| H03 / 候选 seed 29 | 投诉记录明确不能删除 | 输出“客服需删除该订单的投诉记录” | 强化提示词仍可能反转禁止动作 |
| S05 / 候选 seed 29 | 简短安全培训记录 | 重复同一摘要直至 token 上限 | 等待、阅读成本与设备消耗增加 |

原版也存在周期 / 期限遗漏、英文被翻译和格式不稳定；候选没有解决这些问题。数字能出现在摘要里不代表单位、状态和归属被正确保留。

## 为什么不继续堆提示词

发现样本暴露问题后，候选添加了数值单位、状态、引用指令、禁止补全、输出语言等通用规则。候选对部分发现样本有所改善，却在额外样本和另一个种子下退化。因此拒绝将“规则更详细”当成“质量更好”的代理指标。

下一轮应分别测试语言路由、结构化事实提取与摘要生成、重复检测和更合适的模型候选，每次只改变一个因素；新增样本单独保留，避免只对发现集调参。当前交付继续保留原音频、时间戳与编辑；关键行动不自动执行。

这次结论足以否决候选，尚不足以决定哪一个替代方案最好。固定音频集与真机测试仍验证 ASR、端到端耗时和恢复，与本诊断分开。

## 复现与检查

```bash
python3 -m venv /tmp/stayword-eval
/tmp/stayword-eval/bin/pip install -r projects/02-stayword/evaluation/summary-probe/requirements.txt
/tmp/stayword-eval/bin/python projects/02-stayword/evaluation/summary-probe/run_probe.py --output /tmp/stayword-source.json
/tmp/stayword-eval/bin/python projects/02-stayword/evaluation/summary-probe/run_probe.py --candidate --output /tmp/stayword-candidate.json
```

额外样本加 `--cases projects/02-stayword/evaluation/summary-probe/holdout.json`。需要 Apple Silicon、已展开的模型权重。不同运行库或硬件不保证逐字相同，比较前先核对指纹和参数。[MLX LM 官方运行说明](https://github.com/ml-explore/mlx-lm)

- 发现样本：[cases.json](cases.json)；额外样本：[holdout.json](holdout.json)；候选：[candidate-policy.txt](candidate-policy.txt)。
- 原版输出：[发现集](results.json) / [额外集](holdout-source.json)。
- 候选输出：[发现集](candidate-results.json) / [额外集](holdout-candidate.json)。
- 所有实际输出均保留，包括失败；没有将合成材料说成真实客户记录。

[标注汇总脚本](summarize_review.py)可重建逐项记录与计数；其中判定是显式保存的助手标注，不是自动事实评判器。
