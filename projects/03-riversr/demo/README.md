# RiverSR 研究产物与应用原型

[返回项目](../README.md) · [研究案例](../docs/case-study.md) · [Quick start](../docs/quick-start.md)

## 早期 Full50 研究产物

一套可复用的研究成果，需要让使用者知道输入是什么、怎样比较模型、结果能回答什么，以及如何继续实验。我按这个顺序组织交付。

| 产物 | 直接查看 | 可用于什么 |
| --- | --- | --- |
| 数据版本 | [5,600 站点构建 manifest](../src/river_sr/data/processed/training/sr_full50_v2_manifest.json) · [Full50 定义](../src/river_sr/training/base/v3/release/full50_predictors.txt) | 检查样本构成、来源、特征和版本变化 |
| 验证方法 | [支流方法对照](../src/river_sr/training/base/v2/RESULTS.md) · [完整水系科学设计](../src/river_sr/training/base/v3/SCIENTIFIC_DESIGN.md) | 按预测场景选择验证条件 |
| 模型比较 | [Base V3 严格验证摘要](../src/river_sr/training/base/v3/validation/README.md) | 在同口径下比较模型，检查均值表现与迁移差异 |
| 模型配方 | [RF 配方](../src/river_sr/training/base/v3/release/rf_recipe.json) · [预处理统计](../src/river_sr/training/base/v3/release/training_medians.csv) | 理解正式模型的输入和训练配置 |
| 研究结论 | [冻结结论](../src/river_sr/training/base/v3/release/scientific_conclusion.md) · [区域失败诊断](../src/river_sr/training/regional_expert/regional_failure_audit/results/FAILURE_AUDIT.md) | 确定可用范围，安排下一轮信息采集和实验 |
| 运行追溯 | [版本及二进制哈希](../src/river_sr/training/base/v3/release/final_manifest.json) | 将配方、结果与正式运行对应起来 |

模型二进制与完整 HPC 归档未随作品集附带。现有输入、配方及冻结摘要可直接阅读，轻量复核不需要重训。

## 后续成果：Natural90、Human17 与应用验证

后续研究已经形成自然基线、增量配对实验和生物基准准备成果。当前作品集先收录[原始执行回报整理](../evaluation/later-research-records.md)，不以早期 Full50 的文件代替后续模型。

| 后续交付 | 执行回报中的成果 | 本作品集呈现 |
| --- | --- | --- |
| Natural90 主线 | 全球 isoscape、三算法迁移比较、Figure 7、Tables S15/S16 | 5,543 站点的人群口径、共同失败与环境域结果 |
| Human17 增量研究 | 修正后的 Tables S4/S5/S11/S12、Figure S6、校验清单 | 15 个算法×迁移单元的配对表、H13 修复与最终决策 |
| 生物应用准备 | 冻结 population registry、study summary 与 benchmark protocol | 四类集合规模、独立性与进入预测对照的条件 |

后续模型二进制和原图文件目前未随仓库收录。这里的科研全球 isoscape 与下面的早期 Web 查询原型分别管理。

## 如何读早期模型结果图

![正式模型比较与迁移诊断](assets/model-evidence.png)

**左图是选型，右图是使用条件。** 相同水系隔离验证下，RF 的误差更低；但两个模型都未命中 29 个极高值站点，而全量训练拟合可以命中其中绝大多数。两部分共同支持“选择 RF 作为连续预测基线，同时继续研究极端值迁移”的判断。

图表读取 Base V3 冻结 CSV，由 [render_figures.py](render_figures.py) 生成。这里展示的是正式实验数据；模型比较与尾部命中的具体汇总口径见[首页](../README.md)。

## 地图：研究成果的交互探索

**以下是已有工程的合成数据原型，展示查询交互；尚未连接真实模型。**

![RiverSR 地图交互原型，使用合成数据](assets/map-prototype.png)

使用流程是：在 Sample Query 输入同位素条件 → 点击 Run → 查看空间展示 → 修改条件并重新查询。截图来自 2026-10-17 运行的 `sr_o_map_web_pro`，示例在 Strontium central 50% 输入 0.7100，其余输入为空。底图 attribution 保留在界面中。

这个原型探索了研究结果如何被查询，但还有一个关键接口需要接通：域模块已经生成网格分值，地图颜色当前却使用独立展示函数。因此，现有画面可以展示界面组织，不能作为实际来源概率或模型推理证据。

## 接入真实研究结果的验收顺序

| 顺序 | 要完成的接口 | 如何确认完成 |
| --- | --- | --- |
| 1 · 查询与显示一致 | 地图颜色、图例与数值读取同一查询输出 | 固定输入能重复得到同一结果，改变输入后各显示同步响应 |
| 2 · 位置与特征一致 | 坐标匹配、所选模型的特征版本和缺失处理一致；Full50 与 Natural90 分开管理 | 对已知站点逐项核对输入，返回模型和数据版本 |
| 3 · 预测与解释一致 | 连续值、输入支持范围和经验证的不确定性一起返回 | 对支持不足区域给出明确状态，不把连续值称为风险概率 |
| 4 · 来源查询成立 | 加入测量误差、预测误差、空间先验和似然假设 | 用已知来源样本检验空间覆盖及校准后再解释为来源推断 |

以上是 Web 接入的验收计划。后续科研全球图及配对结果已在执行回报中出现；拿到对应原始图表后再收录，不把当前合成原型标成 Natural90 的真实展示。
