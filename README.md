# RiverSR

RiverSR 用于重建河流水体锶同位素模型的训练、修正、区域专家模型与全球预测流程。

项目按历史工作顺序逐项复现。每个项目有独立入口、配置、测试和输出；完成并验收后冻结，再进入下一个项目。

## 顶层结构

- `data/`：共享原始数据，以及按数据管线项目隔离的中间态和正式处理结果。
- `data_pipeline/`：从共享 raw 数据生成 processed 数据的项目级管线。
- `training/`：Base、全球修正和区域专家训练项目。
- `prediction/`：最终全球预测流程。
- `reference/`：历史资料与最终对比材料，不参与任何运行链路。
- `environment/`：本机和超算共用的 R 依赖定义、启动脚本与运行配置。
- `hpc/`：后续超算提交与运行约定。

## 当前阶段

目录和独立入口已经完整建立。当前激活项目是 `data_pipeline/base_observations`；其他入口处于明确的 scaffold 状态，轮到该项目时再实现，不会假装运行成功。

## 复现顺序

1. `data_pipeline/base_observations`
2. `training/base/v0`
3. `training/base/v1`
4. `training/global_correction/global_high_sr_risk`
5. `training/global_correction/high_sr_correction_feasibility`
6. `training/base/v2`
7. `training/regional_expert/regional_risk_v1`
8. `training/regional_expert/regional_risk_v1_1`
9. `training/regional_expert/regional_risk_v2`，含 `risk_v2_failure_audit`
10. `data_pipeline/supplement_observations`
11. `training/base/v3`
12. `data_pipeline/global_covariates`
13. `prediction/global_prediction`

历史比较由 Codex 读取 `reference/` 和各项目 `results/` 完成；任何训练或预测入口都不得依赖 `reference/`。
