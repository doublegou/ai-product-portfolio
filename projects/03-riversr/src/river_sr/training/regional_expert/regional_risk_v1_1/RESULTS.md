# Regional Risk V1.1 — Final Result

## Final status

`RANKING_SIGNAL_NOT_OPERATIONAL_GATE`

运行接纳：**通过——最终结果与上一轮及历史指标处于同一量级，复现相同科学结论，并作为当前正式证据。**

本次正式运行已完成。Run ID 为 `regional_risk_v1_1_20260817_corrected_r1_final`，34/34 tasks、578 GAM fits、34 Platt calibrators、68 thresholds 和 744 条 Outer OOF predictions 均完整；全部 GAM 和 calibrator 收敛。

## Primary Gate

| Model | Metric | Historical | Previous run | Final run |
|---|---|---:|---:|---:|
| Environment-only GAM | Background FPR | 10.7% | 10.7% | 10.7% |
| Environment-only GAM | Recall | 40.5% | 41.6% | 40.5% |
| Environment-only GAM | Precision | 36.0% | 38.0% | 36.0% |
| Combined GAM | Background FPR | 6.9% | 7.9% | 6.9% |
| Combined GAM | Recall | 44.1% | 45.5% | 44.1% |
| Combined GAM | Precision | 31.7% | 31.5% | 31.4% |

Positive-branch coverage remains `7/14` for Environment-only and `6/14` for Combined. Extreme-branch coverage remains `1/4` for both. Neither candidate passes all frozen targets.

复现指标与历史结果处于同一范围，模型相对表现、branch覆盖和失败原因一致。

## Strict Gate

- Environment-only GAM：历史、上一轮和最终运行 Recall 均约为 1.3%。
- Combined GAM：历史、上一轮和最终运行 Recall 均约为 26.3%，最终运行 Outer background FPR 为 6.9%。
- 两个模型在最终运行中均未识别任何 `Sr >= 0.80` 站点。

## Conclusion

V1 的 GAM 确实包含可迁移的喜马拉雅区域高-Sr ranking signal，但经过严格 Nested LOBO、inner-only Platt calibration 和 inner-only threshold selection 后，该信号仍不足以形成可靠的跨-branch operational Risk Gate。

最终结果保持历史 V1.1 结论，而且主要 Primary 指标比上一轮更接近历史记录。按冻结停止规则，不再调整当前 GAM、calibrator 或 threshold rule；保留 V1 和 V1.1 结果，不拟合最终模型，不创建 release。Regional Risk V2 为独立实验。

Slurm stdout/stderr 中没有 fatal error 或 warning 行。34 个 Platt calibrator 均收敛且 slope 为正；其结构化诊断各记录一条由非整数 branch 权重引起的 binomial warning，这是冻结权重方案的预期数值提示，不影响完整的外部 OOF Gate 评价。

## Provenance

- Source commit: `e741c81ada30abec52a688eff0ea99f2fc1a20b1`
- Run ID: `regional_risk_v1_1_20260817_corrected_r1_final`
- Data MD5: `6fe0d27c33b47956f21d0e8d6e832ec5`
- Config MD5: `e34a9d869a819bd26e49dcb7c42803a8`
- Fold manifest MD5: `6d93ac7589be18105cde77a8e70a17ab`
- Archive: `regional_risk_v1_1_regional_risk_v1_1_20260817_corrected_r1_final.tar.gz`
- Archive size: `1,249,292` bytes
- Archive SHA-256: `e6eefc3a72f097e293d42e4b593960f33ac0c15f32f29ade940219416a36a094`
