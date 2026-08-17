# Training

训练层按工程链路分为三个项目组：`base/`、`global_correction/`、`regional_expert/`。

当前已完成并冻结 `base/v0/`、`base/v1/`、`base/v2/` 和 `base/v3/`。Base V3在5,600站点的全球连续回归竞争中选择RF，但严格水文系统隔离OOF对29个`Sr >= 0.80`站点和5个极高值水系的命中均为0，因此发布范围不包括高-Sr发现或风险筛查。

两个Global high-Sr feasibility项目以及喜马拉雅区域风险V1、V1.1和V2的正式实验均已完成。Regional Risk V2的四个RF/boosting × Full50/Process14候选未通过完整Gate，停止当前模型与特征路线，未拟合full-data expert，未创建release。
