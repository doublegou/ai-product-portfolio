# Regional Risk V1.1 — Nested calibration and Gate validation

本项目直接继承 Regional Risk V1 冻结的 372 个 Himalayan stations、17 个 regional branches、Environment-only GAM 与 Combined GAM。它不读取 Regional Risk V2 的配置、特征、模型或结果。

V1.1 只回答一个问题：V1 已发现的跨 branch ranking signal，经过严格 Nested LOBO、inner-only Platt probability calibration 与 inner-only threshold selection 后，能否形成可迁移的 operational Risk Gate。

## 冻结方法

- Outer：完整留出 1 个 regional branch；共 17 folds。
- Inner：在剩余 16 branches 内执行 exhaustive LOBO，产生真正的 development OOF raw GAM probabilities。
- Calibration：branch-sqrt-weighted Platt logistic recalibration；predictor 为 `logit(clip(raw_probability, 1e-6, 1-1e-6))`；slope 必须为正。
- Threshold：只使用 calibrated inner OOF；Primary 的 background FPR cap 为 10%，Strict diagnostic 为 5%；依次最大化 weighted Recall、weighted Precision、threshold。
- Primary evidence targets：Recall ≥ 50%、Precision ≥ 30%、positive-branch coverage ≥ 50%、extreme-branch coverage ≥ 75%，且 realized Outer OOF background FPR ≤ 10%。
- Strict 5% Gate 只作压力诊断，不使用 Regional Risk V2 的标准。

每个 `Outer × model` 是一个原子任务，内部拟合 16 个 Inner GAM 与 1 个 Outer GAM。正式设计共 34 个任务、578 个 GAM fits、34 个 Platt calibrators、68 个 thresholds 和 744 条 Outer OOF predictions。

## 本地工程检查

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" training/regional_expert/regional_risk_v1_1/scripts/run.R --stage prepare
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" training/regional_expert/regional_risk_v1_1/scripts/run.R --stage check
```

`prepare` 只冻结输入签名、Outer assignments 与 task manifest。`check` 运行静态契约、合成 GAM 接口、Platt、threshold tie-break 与 no-trigger 边界测试；不会拟合任何正式 Himalayan task。

正式训练由 `hpc/slurm/regional_risk_v1_1/` 移交给专门的超算管理任务。本地不得隐式启动全量训练。

## 重建边界

历史 threshold 源码未保存在当前工作区。`unique calibrated probabilities + no-trigger sentinel` 被显式登记为方法级前向复现假设；正式输出会记录是否实际选择过 no-trigger。除此之外，校准器、权重、FPR caps、tie-break 和 evidence targets 均按恢复的 V1.1 冻结合同实现。
