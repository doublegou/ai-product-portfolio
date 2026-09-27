# RiverSR

RiverSR 实现河流水体锶同位素模型的数据处理、基础训练、修正、区域专家模型与全球预测流程。正式运行只依赖当前冻结的上游资产。

## 顶层结构

- `data/`：共享原始数据、共享临时中间态，以及按数据项目分层的正式处理结果。
- `data_pipeline/`：从共享 raw 数据生成 processed 数据的项目级管线。
- `training/`：Base、全球修正和区域专家训练项目。
- `prediction/`：最终全球预测流程。
- `reference/`：外部资料与最终对比材料，不参与任何运行链路。
- `env/`：唯一的 R 环境，包含依赖锁、启动脚本和本机/超算配置。
- `hpc/`：后续超算提交与运行约定。

## 当前阶段

- Full50 数据管线与 Base V0–V3 已完成并冻结。
- Base V3 在5,600站点全球模型竞争中选择 RF；它被接受为全球连续Sr回归模型，但未通过高-Sr水系识别验收。
- Global High-Sr Risk V1 与 High-Sr Correction Feasibility 已完成，结论均为停止继续开发对应 high-Sr 二层模型。
- Base V2 与区域专家 V1、V1.1、V2 的正式实验均已完成；Regional Risk V2 未通过完整 Gate，未创建 release。
- 后续工作进入全球预测与最终成果整合。

## 工程顺序

1. 基础观测数据管线
2. Base Model V0
3. Base Model V1 / Random Forest Train V1
4. Global High-Sr Risk Model
5. High-Sr Correction Feasibility
6. Base Model V2
7. Regional Risk V1
8. Regional Risk V1.1
9. Regional Risk V2 与 Failure Audit
10. 补充数据与全球模型竞争（Base V3）
11. 全球预测

任何数据、训练或预测入口都不得依赖 `reference/`。
