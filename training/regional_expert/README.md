# Regional expert projects

依次复现 `regional_risk_v1`、`regional_risk_v1_1` 和 `regional_risk_v2`；研究区域始终是喜马拉雅。`regional_risk_v1/`已完成严格LOBO顺向复现并冻结为`SIGNAL_FEASIBILITY_ONLY`，未生成Gate、最终expert或release。`regional_risk_v1_1/`直接继承V1冻结数据、branch和两套GAM，已具备Strict Nested LOBO、inner-only Platt calibration与10%/5% Gate验证的工程实现，正式训练由独立HPC工作流接管。V1.1不读取V2；V2的失败审计保留为其内部独立子项目。
