# Training

训练层按历史工作链分为三个项目组：`base/`、`global_correction/`、`regional_expert/`。

当前已实现 `base/v0/`、`base/v1/` 和 `base/v2/`，完成两个 Global high-Sr feasibility 项目，并完成 `regional_expert/regional_risk_v1/` 的喜马拉雅区域风险严格LOBO顺向复现。`regional_expert/regional_risk_v1_1/`已完成方法冻结、Nested LOBO工程实现与本地工程检查，等待独立HPC正式训练；它与`regional_risk_v2/`完全解耦。
