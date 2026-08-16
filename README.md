# RiverSR

RiverSR 用于重建河流水体锶同位素模型的训练、修正、区域专家模型与全球预测流程。

项目按历史工作顺序逐项顺向复现。正式运行只依赖当前冻结的上游资产；历史材料仅用于运行完成后的外部对照。

## 顶层结构

- `data/`：共享原始数据、共享临时中间态，以及按数据项目分层的正式处理结果。
- `data_pipeline/`：从共享 raw 数据生成 processed 数据的项目级管线。
- `training/`：Base、全球修正和区域专家训练项目。
- `prediction/`：最终全球预测流程。
- `reference/`：历史资料与最终对比材料，不参与任何运行链路。
- `env/`：唯一的 R 环境，包含依赖锁、启动脚本和本机/超算配置。
- `hpc/`：后续超算提交与运行约定。

## 当前阶段

- Full50 数据管线、Base V0 和 Base V1 已完成并冻结。
- Global High-Sr Risk V1 与 High-Sr Correction Feasibility 已完成，结论均为停止继续开发对应 high-Sr 二层模型。
- Base V2 已完成 response-blind branch topology、Purged-Branch folds 和 Full50 RF/HPC 工程准备，正式训练尚未启动。
- 后续区域专家与全球预测按复现顺序继续推进。

## 复现顺序

1. 基础观测数据管线
2. Base Model V0
3. Base Model V1 / Random Forest Train V1
4. Global High-Sr Risk Model
5. High-Sr Correction Feasibility
6. Base Model V2
7. Regional Risk V1
8. Regional Risk V1.1
9. Regional Risk V2 与 Failure Audit
10. 补充数据与全球模型竞争（后续 Base 版本）
11. 全球预测

历史比较由 Codex 在项目外部执行。任何数据、训练或预测入口都不得依赖 `reference/`。
