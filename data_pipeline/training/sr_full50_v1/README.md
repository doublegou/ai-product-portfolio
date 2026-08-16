# Training / sr_full50_v1 data pipeline

把共享原始观测正向聚合为站点，并与恢复的 V1 冻结预测因子块对齐，生成 Base Model V0 使用的历史兼容 Full50 训练表。

## 边界

- 输入：`data/raw/observation/observation_v1.csv` 与 `data/raw/model_inputs/full50_v1_predictors.csv`
- 正式输出：`data/processed/training/sr_full50_v1.csv`
- 正式运行不读取 `reference/`

## 处理规则

一次性原始数据获取不属于本处理管线。首次运行或原始数据缺失时，单独执行：

```powershell
Rscript data_pipeline/raw_features/run.R
```

正式 release 按以下步骤执行：

1. `01_build_candidate_sites.R`：按两阶段测量身份规则去重，经纬度保留 5 位小数后计算稳定站点 ID，并聚合候选站点。
2. `08_assemble_full50.R`：连接恢复的 4,527 站预测因子块，应用原 complete-P0 规则，输出 4,485 × 121 release。
3. `09_validate_release.R`：校验行列数、50 个预测变量完整性以及冻结预测因子逐值一致性，并写 manifest。

`02`–`07` 保留为官方源 forward-audit 脚本，但不再属于 V1 正式发布链。审计表与历史 V1 并非逐值等价：旧中间成果已经丢失，且旧版存在 7 个流域 override、特定河网坐标和特征 join lineage。它不能替代冻结训练输入。

恢复的预测因子块已从临时 `reference/` 提升为带哈希的数据资产，位于 `data/raw/model_inputs/`。这是对不可再生模型输入的版本化保存，不伪装成可由当前官方栅格逐值重算的原始环境数据。

`config/full50_predictors.txt` 固定了旧版 `M_FULL_MECHANISTIC` 使用的 50 个变量：28 个 P0、7 个本地岩性、10 个地质年龄、1 个岩性熵和 4 个本地/上游环境变量。历史表中的两个 `r50__` 紧凑代理变量属于 Core 模型，因此不计入 Full50。

## 入口

```powershell
Rscript data_pipeline/training/sr_full50_v1/scripts/run.R
```

失败后从第一个缺失的阶段输出继续：

```powershell
Rscript data_pipeline/training/sr_full50_v1/scripts/run.R --resume
```

默认不带参数时完整重跑，避免无意复用旧中间态。`--resume` 仅用于同一轮运行失败后的断点恢复；它根据每一步成功写出的中间文件定位断点，并从第一个缺失步骤继续。也可以按编号单独运行每一步，便于检查中间状态。`common.R` 只提供各步骤共用的路径、站点 ID 和安全写出能力，不是独立处理步骤，因此不编号。
