# Training

训练层按历史工作链分为三个项目组：

- `base/v0`、`v1`、`v2`、`v3`
- `global_correction/global_high_sr_risk`
- `global_correction/high_sr_correction_feasibility`
- `regional_expert/regional_risk_v1`
- `regional_expert/regional_risk_v1_1`
- `regional_expert/regional_risk_v2`
- `regional_expert/regional_risk_v2/risk_v2_failure_audit`

每个项目均有独立入口。只有通过验收的模型才可以登记到 `releases/registry.yml`，供全球预测读取。
