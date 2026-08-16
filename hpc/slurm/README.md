# Slurm

按训练项目保存 Slurm 编排。每个项目只提供一个名为 `run.sh` 的操作入口，作业脚本只调用对应项目的 `scripts/run.R`，不复制训练逻辑。

- `base_v0/run.sh submit [run_id]`：提交 prepare、smoke、20-task validation array 和 finalize 依赖链。
- `base_v0/run.sh bootstrap`：在计算节点恢复同一项目环境中的 V0 必需依赖。
- `base_v0/run.sh status [run_id]`：查看该次运行的队列和历史状态。
- `base_v0/run.sh archive <run_id>`：生成可下载的完整回传包。
- `global_high_sr_risk/run.sh submit [run_id]`：提交无训练 check、15 个 Elastic-net 任务、15 个 Probability RF 任务、完整 OOF 聚合和 feasibility 判定依赖链。
