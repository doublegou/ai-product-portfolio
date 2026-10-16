# RiverSR 技术与验证架构

[返回项目](../README.md)

## 输入、特征与冻结契约

Base V3 输入为 `sr_full50_v2.csv`：5,600 站点，响应变量 `sr87_sr86`，冻结 Full50 预测变量。水文系统来自 HydroBASINS level-6 的 MAIN_BAS，正式设计记载 364 个系统，其中 13 个含 Sr ≥ 0.75，5 个含 Sr ≥ 0.80。站点、水系和特征清单先冻结，再训练。

文本输入按 LF 规范化后计算 SHA-256，二进制按原始字节计算；跨平台换行不会改变输入身份。64 位流域编号通过 bit64 保持精度。数据派生预处理只在当前训练分区拟合，不能用外层测试数据计算填充值等统计量。

来源：[科学设计](../src/river_sr/training/base/v3/SCIENTIFIC_DESIGN.md)、[实现决策](../src/river_sr/training/base/v3/IMPLEMENTATION_DECISIONS.md)、[50 特征清单](../src/river_sr/training/base/v3/release/full50_predictors.txt)。

## 严格嵌套验证

外层 3 repeats × 5 folds，同一完整水系不跨训练与测试；每个外层训练集再建 5-fold 水系隔离内层。每站有 3 次严格 OOF 预测。

内层选择结构与权重，外层只评价冻结候选。RF 池有 378 种结构，XGBoost 有 1,728 种；每个外层任务用相同 48 粗筛 + 16 细化结构预算，各结构比较 W0 / W1 / W2。W2 在四个 Sr 区间的权重为 1 / 2 / 4 / 8；**验收指标不加权**，不能通过给高值更大权重来掩盖实际误差。

内层先以 RMSE 确定 0.5% 范围内候选，再以尾部识别、低值误报、偏差等打破近似并列。算法最终选择用 pooled strict Outer-OOF RMSE，MAE 与绝对偏差作确定性平局规则。两个层次的规则不同，不要混写。

## 模型配方与资源控制

| 项目 | RF | XGBoost |
| --- | --- | --- |
| 冻结结构 | rf_110 | xgb_1535 |
| 主要参数 | mtry 12；min node 1；无放回；sample fraction 0.8 | depth 8；eta 0.05；child weight 5；subsample / colsample 1；lambda 1；alpha 0.1；gamma 0 |
| 权重 / 最终规模 | W2；4,000 树 | W1；118 轮 |
| 轮数控制 | 冻结树数 | 内层最多 3,000 轮，50 轮 patience；冻结内层选中轮数的中位数用于外层拟合 |

算法选定后另做全数据 grouped tuning，选择部署配方。这个分数不是无偏泛化估计。固定配方再做 500 / 1,000 / 1,500 km 空间分块与 reference 分组压力测试，不允许根据 stress 结果再调参。

这些空间压力测试是 EPSG:6933 正方形分块，不能描述成“每个测试站点周围清空相应公里数”的距离缓冲实验。后者属于 Direction 2 提出的另一类设计。

## 运行工程与交付物

正式流程：prepare → 15 RF + 15 XGB 主任务 → 聚合 → 部署调参 → 20 RF + 20 XGB stress → 全数据拟合 → check / release。使用 Slurm 调度，各阶段显式指定 run_id；参数、输入、分组与源码哈希组成追溯契约，不能静默复用不同运行的结果。

交付物包括冻结配方、特征清单、预处理统计、分组清单、主验证及压力测试摘要、科学结论与二进制包哈希。仓库保留紧凑证据；`model_bundle.rds` 在源项目中被 Git 忽略，本作品集没有自动附带该权重。完整 HPC 归档是正式运行的二进制记录，不能把 README 中的 release 状态理解为在线预测服务已经部署。

来源：[release 目录](../src/river_sr/training/base/v3/release/README.md)、[最终 manifest](../src/river_sr/training/base/v3/release/final_manifest.json)。

## 如何解释两种 OOF 汇总

- pooled：5,600 × 3 = 16,800 条预测，用于本次算法比较。不是 16,800 个独立站点。
- site mean：每站 3 次预测先平均，再在 5,600 站点上评价，便于站点与区间诊断。
- training：全量拟合后回看训练数据，只用于容量诊断。

不能混合三种分母，也不能从这三次重复直接构造独立同分布置信区间。本轮审计对冻结摘要做一致性和算术检查，没有重建原始逐站 OOF。

## 地图原型的真实依赖

[isotope.ts](../src/sr_o_map_web_pro/src/domain/isotope.ts) 的 `fieldAt` 生成确定性合成值，查询网格按各输入密度计算与归一化。这个 score 是原型中的相对分值，不是经校准的真实地理来源概率。

[ProbabilityMap.tsx](../src/sr_o_map_web_pro/src/components/ProbabilityMap.tsx) 使用 `displayProbabilityAt(coordinate)` 绘制颜色，尚未直接绑定网格 `cell.score`。因此查询模块单测通过，也不能推出视觉输出正确响应查询。真正接入前应先修复绑定关系、增加输入改变→颜色改变的端到端验收，再接真实栅格、模型版本和不确定性。
