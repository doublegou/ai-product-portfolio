# RiverSR 验证与结果口径

[返回项目](../README.md)

## 本轮实际执行

| 检查 | 结果 | 能说明什么 |
| --- | --- | --- |
| Python 输入与摘要审计 | 16/16 通过 | 站点、区间、哈希与摘要算术一致 |
| 地图现有 Vitest 测试 | 2 文件、15 测试通过 | 合成场、查询计算和边界数据的单测通过 |
| 地图 TypeScript + Vite 构建 | 通过 | 当前工程可生成静态构建 |
| 浏览器输入变更检查 | 0.7100 → 0.7500 后叠加层哈希相同 | 证实地图颜色没有随这组查询变化，不能当预测结果 |
| HPC 模型重训练 | 未执行 | 不新增模型精度或重训成功声明 |
| 原始逐站 OOF 指标重算 | 未执行 | 当前仓库紧凑摘要不是完整原始预测记录 |

审计脚本：[audit_results.py](audit_results.py)；机器可读输出：[results-audit.json](results-audit.json)。地图测试 / 构建记录见 [map-check.txt](map-check.txt)。运行日期：2026-10-17。

16 项为本轮证据一致性检查，不是模型质量测试集大小。正式运行原有的 7 项工程完整性检查另外保存在源工程，不能把两组检查相加后声称更多模型实验。

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

优化笔记中的二层修正数字对应前一次 `high_sr_corr_20260816_r2`；工程最终接受的是 `high_sr_corr_20260817_corrected_r1_final`。后者 Full50 残差 RF 的平均 Raw-Base 改进为 −0.95%，笔记历史版为 −1.64%。两者结论均为 STOP，但不能混用同一表格。本作品集用最终实验数值，保留原笔记用于追溯。

Base V0/V1/V2/V3 的人口、预测情境和汇总口径不同，不能将结果排列成版本越高越好的增长曲线。Direction 2 没有已完成的正式结果，不进入成绩表。

## 地图测试与产品正确性的差距

15 项测试验证合成计算规则，没有证明热力图响应真实模型。代码审查发现颜色走独立 `displayProbabilityAt`，并未直接消费查询 score。本轮还在 Chromium 中分别输入 0.7100 与 0.7500 后执行 Run，叠加图层数据哈希完全相同，与代码发现一致。[交互检查记录](query-interaction.json)

因此截图标记为合成原型，尚不能成为真实预测证据。

依赖安装同时报告 13 项安全告警（2 low、2 moderate、7 high、2 critical）。本轮只整理作品集与运行已有工程，没有自动改写原锁文件；它应保持本地原型用途，正式发布前需逐项核查依赖及可达风险。测试通过不能代替发布验收。
