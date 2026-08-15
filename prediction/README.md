# Prediction

全球预测入口位于 `global_prediction/run.R`。

Prediction 只消费：

- `data/processed/global_covariates`
- `training/releases/registry.yml` 中登记的稳定模型

Prediction 不调用训练项目临时 artifacts，也不读取历史 reference。
