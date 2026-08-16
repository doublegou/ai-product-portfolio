# Base V2 scientific conclusion

Run: `base_v2_full_20260817_r2`

Base V2 的方法级复现得到支持。九套预冻结、response-blind 的 branch designs 中，Purged Branch 在总体 RMSE、MAE、Sr >= 0.75 绝对 Bias 和 branch-macro RMSE 上均为 9/9 优于 Matched Terminal CV。这表明 terminal-component validation 对“新支流”泛化问题过于保守，并系统性低估了普通 Full50 RF 的现实支流泛化能力。

Purged Branch 相比 Naive Branch 未产生稳定的性能优势，但这不否定 purge。Downstream purge 的作用是切断 assessment branch 与水文连通下游训练站点之间的信息通道，而不是提高模型精度。在冻结 Primary 设计 `primary_s05` 上，purge 相比 naive 的 RMSE、MAE 和 branch-macro RMSE 代价分别约为 2.65%、6.00% 和 2.97%，Sr >= 0.75 绝对 Bias 则略有改善。该结果支持将 downstream purge 保留为严格的拓扑隔离约束。

Primary station-mean OOF 在 2,577 个 branch-eligible stations 上得到 RMSE 0.0132624、MAE 0.00460586、R2 0.430985 和 Bias +0.0004006。结果与历史 Base V2 的样本结构、不同验证尺度表现及科学方向高度一致，可认定为成功的方法级 forward reconstruction。

普通 Full50 RF 的 extreme-Sr 收缩仍然存在：Sr >= 0.75 Bias 为 -0.0319597，Sr >= 0.80 Bias 为 -0.147928；Primary OOF 的观测最大值为 1.06374，而预测最大值为 0.840930。Base V2 因此被接受为面向新支流泛化的 ordinary RF base model，不应被解释为 high-Sr 问题已经解决。

结论：接受 `base_v2_full_20260817_r2` 作为 Base V2 的冻结候选；允许创建模型 release。Benchmark 仅验证 branch geometry，不参与最终超参数选择。
