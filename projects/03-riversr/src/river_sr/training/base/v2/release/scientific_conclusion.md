# Base V2 scientific conclusion

Run: `base_v2_full_20260817_corrected_r1_final`

Base V2 的方法级复现继续得到支持。九套预冻结、response-blind 的 branch designs 中，Purged Branch 在总体 RMSE、MAE、Sr >= 0.75 绝对 Bias 和 branch-macro RMSE 上均为 9/9 优于 Matched Terminal CV。这说明 terminal-component validation 对“新支流”泛化问题过于保守，并系统性低估普通 Full50 RF 的现实支流泛化能力。

Purged Branch 相比 Naive Branch 仍未产生稳定的性能优势。Downstream purge 的职责是切断 assessment branch 与水文连通下游训练站点之间的信息通道，而不是保证提高精度。在冻结 Primary 设计 `primary_s05` 上，purge 相比 naive 的 RMSE、MAE 和 branch-macro RMSE 分别有约 2.47%、5.79% 和 2.67% 的代价，Sr >= 0.75 绝对 Bias 略有改善。该结果继续支持将 downstream purge 保留为严格拓扑隔离约束。

Primary station-mean OOF 在 2,577 个 branch-eligible stations 上得到 RMSE 0.0133358、MAE 0.00458687、R2 0.424667 和 Bias +0.0003784。相对上一轮 r2，RMSE 变化 +0.55%，MAE 变化 -0.41%，branch-macro RMSE 基本不变；最终 ordinary RF recipe 与 fingerprint 完全相同。

普通 Full50 RF 的 extreme-Sr 收缩仍然存在，并略有加重：Sr >= 0.75 Bias 为 -0.0328088，Sr >= 0.80 Bias 为 -0.152258；Primary OOF 的观测最大值为 1.06374，预测最大值为 0.825436。Sr >= 0.80 的同阈值 Recall 为 1/10。Base V2 因此被接受为面向新支流泛化的 ordinary RF base model，不应被解释为 high-Sr 问题已经解决。

结论：接受 `base_v2_full_20260817_corrected_r1_final` 作为 Base V2 最终冻结结果，并以该 run 更新 release。Benchmark 仅验证 branch geometry，不参与最终超参数选择。
