# Training

训练层按历史工作链分为三个项目组：`base/`、`global_correction/`、`regional_expert/`。

当前已实现 `base/v0/`、`base/v1/` 和 `base/v2/`，完成两个 Global high-Sr feasibility 项目，并完成喜马拉雅区域风险V1、V1.1与V2的严格LOBO顺向实验。Regional Risk V2的四个RF/boosting × Full50/Process14候选均未通过完整Gate，停止当前模型与特征路线，未拟合full-data expert，未创建release。
