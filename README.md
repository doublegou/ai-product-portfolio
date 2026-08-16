# RiverSR

RiverSR 用于重建河流水体锶同位素模型的训练、修正、区域专家模型与全球预测流程。

项目按历史工作顺序逐项复现。当前只实现正在处理的数据管线和 Base Model V0；后续训练项目先保留空目录，轮到时再加入内容。

## 顶层结构

- `data/`：共享原始数据、共享临时中间态，以及按数据项目分层的正式处理结果。
- `data_pipeline/`：从共享 raw 数据生成 processed 数据的项目级管线。
- `training/`：Base、全球修正和区域专家训练项目。
- `prediction/`：最终全球预测流程。
- `reference/`：历史资料与最终对比材料，不参与任何运行链路。
- `env/`：唯一的 R 环境，包含依赖锁、启动脚本和本机/超算配置。
- `hpc/`：后续超算提交与运行约定。

## 当前阶段

当前只落地：

- `data_pipeline/raw_features`：一次性准备共享原始特征，不进入日常 Full50 运行链路。
- `data_pipeline/training/sr_full50_v1`：Base V0 使用的 Full50 训练数据管线。
- `training/base/v0`：第一个模型复现项目。

`sr_full50_v1` 已完成从 raw 特征源到 Full50 表的项目级编排，正式训练数据仍在处理。Base V0 的 Full50 nested-CV、RF 调参、final consensus、全量拟合和 release 冻结代码已经落地，待正式数据完成后准备 folds 并启动训练。V1、V2、V3、全球修正和区域专家项目目前只有空目录。

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
