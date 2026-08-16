# Base Model V0

这是 Full50 Base Model V0 的方法级复现。项目只训练一套 50 变量、不加权、无尾部修正的 `ranger` Random Forest 回归模型，不包含旧工程中的 28/42 变量模型，也不包含后续 QRF、XGBoost、分类器或区域专家。

## 方法

- 响应变量：`sr87_sr86`。
- 预测变量：读取 `data_pipeline/training/sr_full50_v1/config/full50_predictors.txt` 中冻结的 50 个变量及其顺序。
- Spatial CV：500、1000、1500 km；每种 5 个 Outer folds，每个 Outer training 内重新建立 3 个 Inner folds。
- Reference CV：完整 `reference_id` 分组进入 5 个 Outer folds；每个 Outer training 内重新建立 3 个 grouped Inner folds。
- Fold 构造移植旧 R51a/R51b：手工球面正弦投影、完整 unit 分配、按行数贪心平衡、固定 seed、outcome-blind。
- 每个 fold 的中位数只由该 fold 的训练部分计算。
- 调参网格：`mtry = round(sqrt(p), p/4, p/2)`、`min.node.size = 5/15`、`sample.fraction = 0.7/1.0`、`replace = FALSE`，共 12 组。
- Inner/Outer/Final 树数分别为 500、1500、3000。
- 1000 km 是 Primary performance evaluation。
- Final 参数从 500/1000/1500 km 共 15 个 spatial tasks 按旧 R56a consensus 选出；reference validation 不参与。

## 目录

- `config/`：模型和运行配置。
- `R/`：fold、插补、指标、调参和 consensus 的公共函数。
- `scripts/`：六个阶段和统一入口。
- `folds/`：V0 公用且冻结的数据划分，不按 run 重复生成。
- `validation/`：20 个正式 Outer validation tasks 的公用结果，不按 run 重复生成。
- `runs/<run_id>/`：某次最终汇总运行的模型、报告、配置和日志。
- `release/`：唯一一套经确认后冻结的 V0 模型快照，不设置 release ID。

## 首次准备

```powershell
Rscript training/base/v0/scripts/run.R --stage prepare
```

首次数据准备完成后执行一次。它运行输入校验并生成公共 folds。之后 smoke/full 只做快速数据指纹检查，不重复执行完整的 01、02，也不会静默重建 folds。

## Smoke

```powershell
Rscript training/base/v0/scripts/run.R --mode smoke
```

Smoke 使用冻结 folds 中的 1000 km fold 1，但把少量树结果写入 `runs/<run_id>/smoke/`，不会污染正式 validation。

## 正式训练

本地顺序执行全部 20 个任务、consensus、最终模型和汇总：

```powershell
Rscript training/base/v0/scripts/run.R --mode full
```

单独执行一个任务，供 Slurm Array 使用：

```powershell
Rscript training/base/v0/scripts/run.R --mode full --scheme spatial_500 --outer-fold 1
```

可用 scheme 为 `spatial_500`、`spatial_1000`、`spatial_1500`、`reference`。已完整写出的 task 默认跳过，以便续跑；只有显式传入 `--force` 才覆盖指定 task。

## 冻结唯一 Release

确认某个 full run 后执行：

```powershell
Rscript training/base/v0/scripts/run.R --release <run_id>
```

模型直接写入 `release/`。如果那里已经存在冻结模型，默认拒绝覆盖。
