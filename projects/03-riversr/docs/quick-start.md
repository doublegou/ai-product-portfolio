# RiverSR · Quick start

[返回项目](../README.md)

## 路径一：下载模型并复核原始预测

在作品集仓库根目录执行。需要 Git LFS 和 Python 3；这条路径不依赖 R，也不提交训练任务。

```bash
git lfs install
git lfs pull --include="projects/03-riversr/src/river_sr/training/base/v3/release/*.rds,projects/03-riversr/src/river_sr/training/base/v3/runs/base_v3_full_20260817_r2/models/*.rds" --exclude=""
python3 projects/03-riversr/evaluation/reproduce_predictions.py
```

预期 `passed: true`，Primary 33,600 行、站点均值 11,200 行、stress 44,800 行。这些行包含两种算法及重复/验证方案，不是新增独立样本。脚本核对原始预测与冻结分组、重算主指标、校验两份最终模型，输出 `evaluation/prediction-reproduction.json` 和 `demo/site-review.csv`。若模型仍是 LFS 指针，哈希检查会失败，应先完成下载。

这条路径复核历史结果，未执行新推理。冻结 RF 模型需要原工程的 R / ranger 环境；模型对象内包含 `model`、`predictors`、`medians`、`recipe` 和数据版本。推理前必须按 `predictors` 的顺序构建输入，并使用 bundle 中的中位数处理非有限值；接口见 [v3_fit_predict](../src/river_sr/training/base/v3/R/common.R)。在训练站点上的全量模型预测仅用于拟合检查，不能替代留出评估。

### 不下载模型时，先检查冻结摘要

无需训练模型。从作品集仓库根目录执行（Python 3，仅标准库）：

```bash
python3 projects/03-riversr/evaluation/audit_results.py
```

预期输出 `passed: true`、`checks: 16`、RF 相对 pooled RMSE 降幅约 2.7568%。脚本读取现有训练人口与冻结摘要，校验站点唯一性、分段数量、7 份文件哈希、重复实验与 pooled 口径、极高值漏检和三次重复的比较方向；输出 `evaluation/results-audit.json`。

这验证的是输入和摘要的一致性，不会重训练、联网下载数据或重新生成逐站 OOF。要看指标来源，直接打开 [Primary pooled CSV](../src/river_sr/training/base/v3/validation/primary_pooled_metrics.csv) 与 [站点均值 CSV](../src/river_sr/training/base/v3/validation/primary_site_mean_metrics.csv)。

## 路径二：运行现有地图交互原型

需要 Node.js 与 npm，安装版本以工程锁文件和依赖要求为准。

```bash
cd projects/03-riversr/src/sr_o_map_web_pro
npm ci
npm test
npm run build
npm run dev -- --host 127.0.0.1
```

打开终端给出的本地地址。输入同位素值、运行查询，再修改输入并重跑。预期可操作表单并查看地图；底图需要网络。**这是合成数据原型，颜色未直接绑定查询分值；不能把画面作为真实地理来源结论。** 已知问题和真实截图见[演示记录](../demo/README.md)。

## 路径三：检查完整研究工程

进入 `projects/03-riversr/src/river_sr`，先阅读 [环境说明](../src/river_sr/env/README.md) 与 [Base V3](../src/river_sr/training/base/v3/README.md)。R、数据空间依赖和完整权重不等同于作品集阅读环境。

工程提供 `Rscript training/base/v3/scripts/run.R prepare` 与 `smoke --run-id local_smoke`；prepare 会写准备产物，应在独立副本中运行。正式实验面向 Slurm，遵循显式 run_id、冻结配置和数据契约。完整实验需要对应数据资产与计算环境；这里的轻量阅读和复核路径不依赖全量重训。

`release/model_bundle.rds` 已通过 LFS 收录。作品集保留正式 Base V3 的两份最终模型和预测记录；完整历史/smoke 运行及逐折模型可从[上游固定提交](https://github.com/triplemengpaper/river_sr/tree/ad120936a965608ba43794742b18d5caebe68b9d)按需取得。当前复核范围为文件与原始预测；重新训练或执行推理需配置上述 R 环境。

## 路径四：查看后续研究与训练证据

Natural90 / Human17 的配对结果、共同失败及生物应用基准见[后续研究记录](../evaluation/later-research-records.md)。这部分目前没有附带 HPC 模型快照，不使用早期 Full50 配方替代。

从仓库根目录重新汇总已保留的任务日志：

```bash
python3 projects/03-riversr/evaluation/summarize_training.py
```

脚本仅读取日志、元数据和配置，输出 `training-evidence.json`；不会提交训练任务。预期覆盖 119 份任务日志，Base V3 Primary 配置预算为 28,830 次 fit 调用。
