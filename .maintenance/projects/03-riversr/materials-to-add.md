# RiverSR 后续材料清单

**已补齐：** Base V3 最终 RF / XGBoost 模型、逐站预测、正式运行记录和原始数据源清单。以下仍需查找后期研究与真实使用材料。

优先找能够将“研究判断”与“实际交付”连接起来的小包。以下目录来自历史执行回报；未知的文件名按内容说明，没有假定其已生成。大体积模型可以先提供配方、版本和 manifest，再补二进制。

### 1 · 后期全球预测图及其模型结果（最优先）

- **找什么：** Natural90 最终全球预测图、图注；与该图对应的模型/特征版本、测试方案和结果汇总表。另附 Figure 7 与 Tables S15/S16 的原件，展示困难环境诊断。Figure 7 不直接当作全球预测图。
- **已知位置：** HPC 的 `river_sr_isoscape_v3_staging/`。共同失败原件位于子目录 `FINAL_M1_COMMON_FAILURE_HG_RECOMPUTE_AND_RECONCILIATION_V1/`。全球预测图及最终模型的精确子目录尚未确认，可按 `Natural90`、`M1`、`isoscape`、`final_manifest` 查找。
- **补上后有什么价值：** 首页可直接展示真正的后期研究成果，并将预测、模型选择和可靠性说明对应起来；精确指标也可从执行回报升级为原始文件证据。

### 2 · 一个真实研究使用案例（最优先）

- **找什么：** 已实际分析过的河流/站点/生物记录，包含研究问题、输入位置和测量、使用的模型版本、输出图表或数值，以及据此作出的解释或下一步决定。研究报告中的一页或一次真实分析记录都可以。
- **有价值的截图：** 输入与对象、真实预测/对照结果、结论所在页面；每张截图保留能对应版本或样本的上下文。若有合作研究中的反馈、汇报结论或后续采用记录，一并提供可分享部分。
- **补上后有什么价值：** 让读者看到从研究问题到使用结果的完整过程，并区分已经使用的成果与后续应用设想。当前没有这一案例的确定文件名；若尚未做过，则保留为下一阶段验证任务。

### 3 · 后期模型与关键实验的小型复核包

- **Natural90：** 最终模型配方、特征字典、预处理说明、分组/测试身份、评估汇总与模型哈希；有独立站点预测表时一起提供。
- **Human17：** `FINAL_HUMAN17_H13_REBUILD_AND_PAIRED_REANALYSIS_V1/` 下修复后的 Tables S4/S5/S11/S12、Figure S6、配对规则和 `11_checksums/HUMAN17_REANALYSIS.sha256`。表文件可能在 `08_supplement/`，已知命名包含 `TABLE_S4_REPAIRED.csv`，同组表与图以原目录为准。
- **查找线索：** 另一台电脑曾使用 `Desktop/global water sr/00_PROJECT_COORDINATION/HANDOFFS/h13_reanalysis.md`；可从这份交接记录定位 HPC 归档。
- **补上后有什么价值：** 将“修复了什么、为什么重跑、结论如何变化”落实到原始结果；保证后期研究使用自己的模型版本。

### 4 · 应用阶段是否有更新结果

- **已知位置：** `AQUATIC_SR_BIOARCHIVE_BENCHMARK_CLOSURE_V1/`。
- **先找：** `09_FINAL_BENCHMARK_POPULATION_REGISTRY.csv`、`10_FINAL_STUDY_LEVEL_BENCHMARK_SUMMARY.csv`、`11_FINAL_BIOLOGICAL_BENCHMARK_PROTOCOL_FROZEN.md`、`12_ROUND3_READINESS.md`。
- **若之后已继续运行：** 补 Round 3 的独立河网匹配、水预测/生物对照、失败样本和结论。若只到 Round 2.5，现有“基准准备完成”的状态保持准确。
- **补上后有什么价值：** 明确应用推进到了哪一步，能否增加真实使用案例，是否已有支持来源判断的证据。

### 5 · 完整训练耗时与费用

- **找什么：** Base V3、Natural90 / Human17 的 Slurm 作业统计导出与实际计费记录。Base V3 的运行 ID、提交代码与 stdout/stderr 已补齐，但日志缺少完整任务起止和资源消耗。统计字段优先包括 `JobIDRaw`、`Submit`、`Start`、`End`、`ElapsedRaw`、`AllocCPUS`、`TotalCPU`、`MaxRSS`、`State`、`ExitCode`。
- **费用材料：** 集群实际计费规则/单价或账单；如按科研配额核算，提供配额消耗记录。
- **补上后有什么价值：** 写出真实端到端耗时、分配核时、失败恢复开销与费用；避免用任务时限、局部日志或申请峰值代替总成本。
