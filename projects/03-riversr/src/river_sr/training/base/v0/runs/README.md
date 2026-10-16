# Runs

每次完整训练或 smoke 使用独立且永久保留的 `<run_id>/` 目录：

```text
<run_id>/
├── config_used.yml
├── run_info.json
├── models/
├── reports/
├── smoke/
└── logs/
```

正式 folds 与 20 个 validation tasks 是 V0 公共资产，分别保存在顶层 `folds/` 和 `validation/`，不在这里重复。

运行内容不提交 Git，但不是临时文件。超算训练完成后，`hpc/slurm/base_v0/run.sh archive <run_id>` 会把本次 run 与公用 folds、validation 一起打包回传。
