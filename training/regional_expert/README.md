# Regional expert projects

`regional_risk_v2/`已完成喜马拉雅区域风险Gate的顺向2×2实验：固定比较probability RF与shallow boosting，以及Full50与Full50 + Process14。17-fold strict Nested LOBO的68/68个Outer任务全部完成；四个候选均未满足完整Gate，最终状态冻结为`NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE`，未拟合full-data model，未创建release。

`regional_failure_audit/`是其下游只读失败审计：固定分析Full64背景重叠、跨branch最近邻和Process14 failure case，不训练模型、不修改threshold或Gate。审计支持结构性信息缺口结论，并将后续工作限定为引入新区域/机制信息的Regional Expert，而不是继续调优同一套64维predictors。
