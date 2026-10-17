# RiverSR 验证与结果口径

[返回项目](../README.md)

## 仓库产物复核

| 检查 | 结果 | 能说明什么 |
| --- | --- | --- |
| Python 输入与摘要审计 | 16/16 通过 | 站点、区间、哈希与摘要算术一致 |
| 地图现有 Vitest 测试 | 2 文件、15 测试通过 | 合成场、查询计算和边界数据的单测通过 |
| 地图 TypeScript + Vite 构建 | 通过 | 当前工程可生成静态构建 |
| 浏览器输入变更检查 | 0.7100 → 0.7500 后叠加层哈希相同 | 证实地图颜色没有随这组查询变化，不能当预测结果 |
| HPC 模型重训练 | 未执行 | 不新增模型精度或重训成功声明 |
| 原始逐站 OOF 与压力测试重算 | 已完成 | 两算法 33,600 行 Primary、44,800 行 stress 与冻结指标一致；测试身份与逐站均值已核对 |
| LFS 最终模型 | 已下载并核对 | RF / XGBoost 哈希与 release 一致；本机没有 R 环境，未声明新增模型推理通过 |

审计脚本：[audit_results.py](audit_results.py)；机器可读输出：[results-audit.json](results-audit.json)。地图测试 / 构建记录见 [map-check.txt](map-check.txt)。运行日期：2026-10-17。

16 项为本轮证据一致性检查，不是模型质量测试集大小。正式运行原有的 7 项工程完整性检查另外保存在源工程，不能把两组检查相加后声称更多模型实验。

## 从原始预测复核结论

[reproduce_predictions.py](reproduce_predictions.py)使用 Python 标准库读取归档，检查 30 个 Primary 任务与 pooled 行一致，测试站点/水系与冻结分组一致，每站三次预测与均值一致，再重算主验证、压力测试和训练拟合指标。输出：[prediction-reproduction.json](prediction-reproduction.json)。

重新计算的 RF 高值分层（实测 ≥0.75）为 136/5,600 站点，贡献 82.90% 的平方误差；其中 29 个极高值站点贡献 69.44%。这些是按实测响应进行的事后诊断，不能据此识别未知站点或声称已建立可靠性概率。

同步保留了 516 个新增源文件；已有文件中仅 `.gitattributes` 更新。2,397 个收录文件与上游选定内容逐字节一致，三个模型路径对应两个 LFS 对象。未收录的历史/smoke 运行和逐折模型仍可在固定上游提交获取。[来源清单](source-sync.json)

## 指标来源与分母

| 材料 | 分母 / 用途 |
| --- | --- |
| [primary_pooled_metrics.csv](../src/river_sr/training/base/v3/validation/primary_pooled_metrics.csv) | 16,800 预测 = 5,600 站点 × 3 repeats；正式算法比较 |
| [primary_site_mean_metrics.csv](../src/river_sr/training/base/v3/validation/primary_site_mean_metrics.csv) | 先平均每站 3 次预测；5,600 站点诊断 |
| [primary_repeat_metrics.csv](../src/river_sr/training/base/v3/validation/primary_repeat_metrics.csv) | 每次重复 5,600 站点；方向稳定性 |
| [training_metrics.csv](../src/river_sr/training/base/v3/release/training_metrics.csv) | 全数据拟合后回看训练集；不能用于泛化承诺 |
| [stress_scheme_metrics.csv](../src/river_sr/training/base/v3/validation/stress_scheme_metrics.csv) | 固定配方、不同空间 / 来源分组；不能据此重新选参 |

两模型 Primary pooled R² 都很低；RF 的相对优势不等于达到高精度用途门槛。没有增加未经预注册的置信区间或统计显著性声明。

## 压力测试没有统一赢家

| 固定配方分组 | RF RMSE | XGBoost RMSE |
| --- | ---: | ---: |
| 500 km 空间块 | 0.015956 | 0.017881 |
| 1,000 km 空间块 | 0.016822 | 0.018169 |
| 1,500 km 空间块 | 0.017571 | 0.017850 |
| Reference 分组 | 0.016076 | 0.015564 |

XGBoost 在 reference 分组 RMSE 更低，说明优势取决于迁移条件；它不改变主验证选择 RF 的规则。空间块大小不是测试站点与训练站点的最小隔离距离，也不能按这些数值画成普适“外推距离曲线”。

## 原始笔记与最终记录的冲突处理

修正实验 RESULTS 同时保留最终运行与历史对照。最终 `high_sr_corr_20260817_corrected_r1_final` 中 Full50 残差 RF 相对 Raw Base 的平均改进为 −0.95%，历史对照为 −1.64%；当前收录的优化笔记也使用 −0.95%。两轮均为 STOP，作品集正文采用最终运行，不将不同运行的残差信号与 Raw-Base 指标拼成一组。

Base V0/V1/V2/V3 的人口、预测情境和汇总口径不同，不能将结果排列成版本越高越好的增长曲线。Natural90 / Human17 已有后续执行回报，另见[后续研究记录](later-research-records.md)。原始 Direction 2 中的精简 Core / lockbox 等方案不能因此自动视为全部实现。

## 地图测试与产品正确性的差距

15 项测试验证合成计算规则，没有证明热力图响应真实模型。代码审查发现颜色走独立 `displayProbabilityAt`，并未直接消费查询 score。本轮还在 Chromium 中分别输入 0.7100 与 0.7500 后执行 Run，叠加图层数据哈希完全相同，与代码发现一致。[交互检查记录](query-interaction.json)

因此截图标记为合成原型，尚不能成为真实预测证据。

依赖安装同时报告 13 项安全告警（2 low、2 moderate、7 high、2 critical）。本轮只整理作品集与运行已有工程，没有自动改写原锁文件；它应保持本地原型用途，正式发布前需逐项核查依赖及可达风险。测试通过不能代替发布验收。

## 训练日志与资源证据

[summarize_training.py](summarize_training.py) 解析仓库保留的 119 份任务日志，选择与当前任务元数据对应的最后完整运行段，并从 Base V3 配置推导 Primary fit 预算。输出见 [training-evidence.json](training-evidence.json)。

Regional V1 / V1.1 的应用窗口分别为 5 / 14 秒；任务时长合计为 55 / 271 秒。这些数值不包含排队、启动及其他阶段，不代表 Base V3 或项目总时长。完整资源请求、计费公式和恢复边界见[训练与资源](../docs/technical-design.md#训练资源耗时与成本)。
